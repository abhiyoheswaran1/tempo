import CloudKit
import Foundation
import Observation
import TempoCore

private final class ChangePage: @unchecked Sendable {
  var records: [CKRecord] = []
  var token: CKServerChangeToken?
  var more = false
  var error: Error?
}
@MainActor @Observable final class CloudSyncService {
  var status = "iCloud sync is off"
  var lastSuccess: Date?
  var pendingUploads = 0
  var restoredRecords = 0
  var busy = false
  var errorMessage: String?
  private var accountChanged = false
  private let container: CKContainer
  private var zoneID = CKRecordZone.ID(
    zoneName: "TempoHistory", ownerName: CKCurrentUserDefaultName)
  private let store: TempoStore
  private var observer: NSObjectProtocol?
  init(store: TempoStore) {
    self.store = store
    let identifier =
      Bundle.main.object(forInfoDictionaryKey: "TempoCloudContainer") as? String
      ?? "iCloud.app.tempo.personal"
    container = CKContainer(identifier: identifier)
    observer = NotificationCenter.default.addObserver(
      forName: .CKAccountChanged, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.accountChanged = true
        self?.status = "iCloud account changed; sync paused"
      }
    }
  }
  func sync() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    errorMessage = nil
    do {
      if let data = try await store.metadata("cloud.lastSuccess") {
        lastSuccess = try? JSONDecoder().decode(Date.self, from: data)
      }
      accountChanged = false
      guard try await container.accountStatus() == .available else {
        throw SyncIssue.accountUnavailable
      }
      let account = StableID.hash(try await container.userRecordID().recordName)
      if let bound = try await store.metadata("cloud.account"),
        String(data: bound, encoding: .utf8) != account
      {
        throw SyncIssue.accountMismatch
      }
      // Binding happens only when the user explicitly enables/retries sync.
      if try await store.metadata("cloud.account") == nil {
        try await store.setMetadata("cloud.account", value: Data(account.utf8))
        try await store.requeueAll()
      }
      guard !accountChanged else { throw SyncIssue.accountMismatch }
      zoneID = CKRecordZone.ID(
        zoneName: "TempoHistory-" + String(account.prefix(16)), ownerName: CKCurrentUserDefaultName)
      status = "Preparing private history"
      try await ensureAccount()
      _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: zoneID))
      try await ensureAccount()
      try await download()
      status = "Uploading local changes"
      for p in try await store.pending() {
        guard !accountChanged else { throw SyncIssue.accountMismatch }
        do {
          try await upload(p)
          try await store.acknowledge(p.id, expectedPayload: p.envelope.payload)
        } catch {
          let ck = error as? CKError
          try await store.deferChange(
            p.id, attempt: p.attempts + 1, retryAfter: ck?.retryAfterSeconds)
          throw error
        }
      }
      try await download()
      pendingUploads = try await store.pendingCount()
      lastSuccess = Date()
      try await store.setMetadata("cloud.lastSuccess", value: try JSONEncoder().encode(lastSuccess))
      status =
        pendingUploads == 0 ? "History is up to date" : "Waiting to retry \(pendingUploads) uploads"
    } catch {
      errorMessage = message(error)
      status = "Sync needs attention"
      pendingUploads = (try? await store.pendingCount()) ?? 0
    }
  }
  private func ensureAccount() async throws {
    guard !accountChanged, let bound = try await store.metadata("cloud.account") else {
      throw SyncIssue.accountMismatch
    }
    let current = StableID.hash(try await container.userRecordID().recordName)
    guard !accountChanged, String(data: bound, encoding: .utf8) == current else {
      throw SyncIssue.accountMismatch
    }
  }
  private func upload(_ p: PendingChange) async throws {
    let recordID = CKRecord.ID(recordName: p.id, zoneID: zoneID)
    for attempt in 0..<4 {
      try await ensureAccount()
      var record: CKRecord
      do {
        record = try await container.privateCloudDatabase.record(for: recordID)
        if let remote = try decode(record), p.envelope.kind == "batch" {
          try await store.apply(remote)
        }
      } catch let e as CKError where e.code == .unknownItem {
        record = CKRecord(recordType: "TempoPayload", recordID: recordID)
      }
      let envelope = try await store.materialize(p.envelope)
      let data = try SensorCompression.encode(JSONEncoder().encode(envelope))
      guard data.count < 800_000 else { throw SyncIssue.batchTooLarge }
      record["kind"] = envelope.kind as CKRecordValue
      record["schemaVersion"] = 1 as CKRecordValue
      record.encryptedValues["payload"] = data as CKRecordValue
      record["checksum"] = StableID.hash(data) as CKRecordValue
      try await ensureAccount()
      do {
        let result = try await container.privateCloudDatabase.modifyRecords(
          saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let saved = result.saveResults[recordID] else { throw SyncIssue.conflict }
        _ = try saved.get()
        return
      } catch let e as CKError
        where (e.code == .serverRecordChanged || e.code == .partialFailure) && attempt < 3
      { continue }
    }
    throw SyncIssue.conflict
  }
  private func decode(_ record: CKRecord) throws -> SyncEnvelope? {
    guard record.recordType == "TempoPayload" else { return nil }
    guard (record["schemaVersion"] as? Int) == 1,
      let data = record.encryptedValues["payload"] as? Data,
      let checksum = record["checksum"] as? String, StableID.hash(data) == checksum
    else { throw StoreError.invalidArchive }
    return try JSONDecoder().decode(SyncEnvelope.self, from: SensorCompression.decode(data))
  }
  private func download() async throws {
    status = "Restoring incremental changes"
    var token: CKServerChangeToken?
    if let data = try await store.metadata("cloud.token") {
      token = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
    var resetTokenOnce = false
    while true {
      guard !accountChanged else { throw SyncIssue.accountMismatch }
      try await ensureAccount()
      let page: ChangePage
      do { page = try await fetchPage(token: token) } catch let e as CKError
        where e.code == .changeTokenExpired && !resetTokenOnce
      {
        token = nil
        resetTokenOnce = true
        continue
      }
      for r in page.records {
        guard !accountChanged else { throw SyncIssue.accountMismatch }
        if let e = try decode(r) {
          try await store.apply(e)
          restoredRecords += 1
        }
      }
      // Advance only after every record in the page committed.
      token = page.token
      if let token {
        try await store.setMetadata(
          "cloud.token",
          value: NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true))
      }
      if !page.more { break }
    }
  }
  private func fetchPage(token: CKServerChangeToken?) async throws -> ChangePage {
    let db = container.privateCloudDatabase
    let zoneID = zoneID
    return try await withCheckedThrowingContinuation { continuation in
      let page = ChangePage()
      let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
      config.previousServerChangeToken = token
      config.resultsLimit = 100
      let op = CKFetchRecordZoneChangesOperation(
        recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])
      op.fetchAllChanges = false
      op.recordWasChangedBlock = { _, result in
        switch result {
        case .success(let record): page.records.append(record)
        case .failure(let error): page.error = error
        }
      }
      // Logical deletion is an immutable revision tombstone; physical deletion is not used.
      op.recordZoneFetchResultBlock = { _, result in
        switch result {
        case .success(let value):
          page.token = value.serverChangeToken
          page.more = value.moreComing
        case .failure(let error): page.error = error
        }
      }
      op.fetchRecordZoneChangesResultBlock = { result in
        if let error = page.error {
          continuation.resume(throwing: error)
        } else {
          switch result {
          case .success: continuation.resume(returning: page)
          case .failure(let e): continuation.resume(throwing: e)
          }
        }
      }
      db.add(op)
    }
  }
  private func message(_ error: Error) -> String {
    if let issue = error as? SyncIssue { return issue.description }
    if let ck = error as? CKError {
      switch ck.code {
      case .quotaExceeded:
        return "Your iCloud quota is full. Collection continues locally; free storage then retry."
      case .networkFailure, .networkUnavailable:
        return "Network unavailable. Your local changes remain queued."
      case .notAuthenticated: return "Sign into iCloud to sync."
      case .permissionFailure: return "Check CloudKit entitlement and schema configuration."
      default: return "iCloud could not complete sync (\(ck.code.rawValue)). Changes remain local."
      }
    }
    return "History validation or storage failed. No download checkpoint was advanced."
  }
  enum SyncIssue: Error {
    case accountUnavailable, accountMismatch, batchTooLarge, conflict
    var description: String {
      switch self {
      case .accountUnavailable: return "iCloud is unavailable. Collection remains local."
      case .accountMismatch:
        return
          "This history belongs to a different iCloud account. Return to the original account; automatic transfer is blocked."
      case .batchTooLarge: return "A sensor batch exceeds the safe upload size. It remains queued."
      case .conflict: return "A concurrent upload changed this batch. Retry to merge it safely."
      }
    }
  }
}
