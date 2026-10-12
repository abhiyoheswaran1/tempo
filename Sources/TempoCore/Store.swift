import CSQLite
import Foundation

public enum StoreError: Error {
  case database(String)
  case invalidArchive, invalidSample, conflictingObservation, unsupportedSchema
}
private final class SQLiteHandle: @unchecked Sendable {
  let pointer: OpaquePointer
  init(path: String) throws {
    var db: OpaquePointer?
    guard
      sqlite3_open_v2(
        path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK, let db
    else { throw StoreError.database("open failed") }
    pointer = db
  }
  deinit { sqlite3_close(pointer) }
}
public actor TempoStore {
  private let allowSynthetic: Bool
  private let handle: SQLiteHandle
  private var db: OpaquePointer { handle.pointer }
  public init(path: String, allowSynthetic: Bool = false) throws {
    self.allowSynthetic = allowSynthetic
    handle = try SQLiteHandle(path: path)
    let db = handle.pointer
    func execute(_ sql: String) throws {
      if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
        throw StoreError.database(String(cString: sqlite3_errmsg(db)))
      }
    }
    try execute(
      "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;"
    )
    var statement: OpaquePointer?
    sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
    let version = sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : 0
    sqlite3_finalize(statement)
    guard version <= 1 else { throw StoreError.unsupportedSchema }
    try execute(
      """
      BEGIN IMMEDIATE;
      CREATE TABLE IF NOT EXISTS observations(id TEXT PRIMARY KEY,device TEXT NOT NULL,kind TEXT NOT NULL,time REAL NOT NULL,payload BLOB NOT NULL);
      CREATE INDEX IF NOT EXISTS observation_time ON observations(time,kind);
      CREATE TABLE IF NOT EXISTS revisions(id TEXT PRIMARY KEY,entity TEXT NOT NULL,kind TEXT NOT NULL,payload BLOB NOT NULL);
      CREATE INDEX IF NOT EXISTS revision_entity ON revisions(entity);
      CREATE TABLE IF NOT EXISTS checkpoints(device TEXT PRIMARY KEY,cursor BLOB NOT NULL);
      CREATE TABLE IF NOT EXISTS outbox(id TEXT PRIMARY KEY,kind TEXT NOT NULL,payload BLOB NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next REAL NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value BLOB NOT NULL);
      CREATE TABLE IF NOT EXISTS rejected(id TEXT PRIMARY KEY,device TEXT NOT NULL,payload BLOB NOT NULL);
      PRAGMA user_version=1;
      COMMIT;
      """)
  }
  private func run(_ sql: String, _ values: [SQLValue] = []) throws {
    let s = try prepare(sql, values)
    defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_DONE else {
      throw StoreError.database(String(cString: sqlite3_errmsg(db)))
    }
  }
  private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
    var s: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else {
      throw StoreError.database(String(cString: sqlite3_errmsg(db)))
    }
    for (i, v) in values.enumerated() {
      let n = Int32(i + 1)
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      switch v {
      case .text(let t): sqlite3_bind_text(s, n, t, -1, transient)
      case .number(let d): sqlite3_bind_double(s, n, d)
      case .blob(let d):
        _ = d.withUnsafeBytes { sqlite3_bind_blob(s, n, $0.baseAddress, Int32(d.count), transient) }
      }
    }
    return s
  }
  private func rows(_ sql: String, _ values: [SQLValue] = []) throws -> [Data] {
    let s = try prepare(sql, values)
    defer { sqlite3_finalize(s) }
    var result: [Data] = []
    while true {
      let code = sqlite3_step(s)
      if code == SQLITE_DONE { break }
      guard code == SQLITE_ROW else {
        throw StoreError.database(String(cString: sqlite3_errmsg(db)))
      }
      let size = Int(sqlite3_column_bytes(s, 0))
      if let p = sqlite3_column_blob(s, 0) {
        result.append(Data(bytes: p, count: size))
      } else {
        result.append(Data())
      }
    }
    return result
  }
  private func transaction(_ body: () throws -> Void) throws {
    try run("BEGIN IMMEDIATE")
    do {
      try body()
      try run("COMMIT")
    } catch {
      try? run("ROLLBACK")
      throw error
    }
  }
  private func queue(_ envelope: SyncEnvelope) throws {
    try run(
      "INSERT INTO outbox(id,kind,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,next=0",
      [.text(envelope.id), .text(envelope.kind), .blob(envelope.payload)])
  }
  private func insertOne(_ m: Measurement, enqueue: Bool) throws {
    guard m.value.isFinite, m.timestamp.timeIntervalSince1970.isFinite,
      m.rrMilliseconds.allSatisfy({ $0.isFinite }),
      m.origin != .synthetic || (allowSynthetic && m.transport == "demo")
    else { throw StoreError.invalidSample }
    let data = try JSONEncoder().encode(m)
    if let existing = try rows("SELECT payload FROM observations WHERE id=?", [.text(m.id)]).first {
      let original = try JSONDecoder().decode(Measurement.self, from: existing)
      guard original == m else { throw StoreError.conflictingObservation }
      return
    }
    try run(
      "INSERT INTO observations VALUES(?,?,?,?,?)",
      [
        .text(m.id), .text(m.deviceID.uuidString), .text(m.kind.rawValue),
        .number(m.timestamp.timeIntervalSince1970), .blob(data),
      ])
    if enqueue && m.origin != .synthetic {
      // One dirty manifest per device and bounded 15-minute bucket, not per sample.
      let bucket = Int(floor(m.timestamp.timeIntervalSince1970 / 900))
      let key = "batch-\(m.deviceID.uuidString)-\(bucket)"
      try queue(
        SyncEnvelope(
          id: key, kind: "batch",
          payload: Data("\(m.deviceID.uuidString)|\(bucket)|\(UUID().uuidString)".utf8)))
    }
  }
  public func insert(_ measurements: [Measurement]) throws {
    try transaction { for m in measurements { try insertOne(m, enqueue: true) } }
  }
  public func measurements(from: Date, to: Date, kinds: [MetricKind]? = nil, limit: Int = 100_000)
    throws -> [Measurement]
  {
    let data = try rows(
      "SELECT payload FROM observations WHERE time>=? AND time<? ORDER BY time DESC LIMIT ?",
      [
        .number(from.timeIntervalSince1970), .number(to.timeIntervalSince1970),
        .number(Double(max(1, min(limit, 100_000)))),
      ])
    let deleted = Set(
      try revisions(kind: "measurementDeletion").compactMap {
        String(data: $0.payload, encoding: .utf8)
      })
    return try data.map { try JSONDecoder().decode(Measurement.self, from: $0) }.filter {
      !deleted.contains($0.id) && (kinds == nil || kinds!.contains($0.kind))
    }.sorted { $0.timestamp < $1.timestamp }
  }
  public func observations(externalID: String) throws -> [Measurement] {
    try rows(
      "SELECT payload FROM observations WHERE json_extract(CAST(payload AS TEXT),'$.externalID')=?",
      [.text(externalID)]
    ).map { try JSONDecoder().decode(Measurement.self, from: $0) }
  }
  public func detectedActivities(
    from: Date, to: Date, maxHeartRate: Double, sourceSegments: [SourceSegment],
    existingWorkouts: [Workout], allowSynthetic: Bool = false
  ) throws -> [DetectedActivityCandidate] {
    AutomaticActivityDetector.detect(
      try measurements(from: from, to: to, kinds: [.heartRate]), maxHeartRate: maxHeartRate,
      now: to, sourceSegments: sourceSegments, existingWorkouts: existingWorkouts,
      allowSynthetic: allowSynthetic && self.allowSynthetic)
  }
  public func dailyRepresentatives(kind: MetricKind, from: Date, to: Date) throws -> [Measurement] {
    let deleted = Set(
      try revisions(kind: "measurementDeletion").compactMap {
        String(data: $0.payload, encoding: .utf8)
      })
    let sql =
      "SELECT payload,MAX(time) FROM observations WHERE kind=? AND time>=? AND time<? GROUP BY CAST(time/86400 AS INTEGER) ORDER BY MAX(time) DESC LIMIT 366"
    return try rows(
      sql,
      [
        .text(kind.rawValue), .number(from.timeIntervalSince1970),
        .number(to.timeIntervalSince1970),
      ]
    ).map { try JSONDecoder().decode(Measurement.self, from: $0) }.filter {
      $0.valid && !deleted.contains($0.id)
    }.sorted { $0.timestamp < $1.timestamp }
  }
  public func nightInputs(_ sleep: SleepSession, sourceSegments: [SourceSegment]) throws -> [String:
    Double]
  {
    let countStatement = try prepare(
      "SELECT COUNT(*) FROM observations WHERE time>=? AND time<?",
      [.number(sleep.start.timeIntervalSince1970), .number(sleep.end.timeIntervalSince1970)])
    let count =
      sqlite3_step(countStatement) == SQLITE_ROW ? sqlite3_column_int(countStatement, 0) : 0
    sqlite3_finalize(countStatement)
    let key =
      "night-v1-"
      + StableID.hash(
        "\(sleep.id)|\(sleep.start.timeIntervalSince1970)|\(sleep.end.timeIntervalSince1970)|\(count)|\(try revisions(kind:"measurementDeletion").count)|\(sourceSegments.count)"
      )
    if let cached = try metadata(key) {
      return try JSONDecoder().decode([String: Double].self, from: cached)
    }
    let samples = CanonicalTimeline.select(
      try measurements(from: sleep.start, to: sleep.end, kinds: [.heartRate]),
      sourceSegments: sourceSegments)
    var inputs: [String: Double] = ["sleepHours": sleep.duration / 3600]
    let coverage = Double(samples.count) / max(1, sleep.duration)
    if coverage >= 0.7 {
      let sorted = samples.map(\.value).sorted()
      inputs["rhr"] = sorted[Int(Double(sorted.count) * 0.1)]
    }
    if let end = samples.last?.timestamp {
      let window = samples.filter { end.timeIntervalSince($0.timestamp) <= 300 }
      let gaps = zip(window, window.dropFirst()).map {
        $1.timestamp.timeIntervalSince($0.timestamp)
      }
      if window.count >= 240, gaps.allSatisfy({ $0 <= 2 }),
        let h = HRV.calculate(window.flatMap(\.rrMilliseconds))
      {
        inputs["rmssd"] = h.rmssd
      }
    }
    try setMetadata(key, value: JSONEncoder().encode(inputs))
    return inputs
  }
  public func commitHistory(
    deviceID: UUID, samples: [Measurement], cursor: Data, rejectedFrames: [Data] = []
  ) throws {
    try transaction {
      guard samples.allSatisfy({ $0.deviceID == deviceID }) else { throw StoreError.invalidSample }
      for m in samples { try insertOne(m, enqueue: true) }
      for f in rejectedFrames {
        try run(
          "INSERT OR IGNORE INTO rejected VALUES(?,?,?)",
          [.text(StableID.hash(f)), .text(deviceID.uuidString), .blob(f)])
      }
      try run(
        "INSERT OR REPLACE INTO checkpoints VALUES(?,?)",
        [.text(deviceID.uuidString), .blob(cursor)])
    }
  }
  public func checkpoint(deviceID: UUID) throws -> Data? {
    try rows("SELECT cursor FROM checkpoints WHERE device=?", [.text(deviceID.uuidString)]).first
  }
  private func validateRevision(_ revision: Revision) throws {
    if !allowSynthetic, revision.kind == "sleep",
      let s = try? JSONDecoder().decode(SleepSession.self, from: revision.payload),
      s.origin == .synthetic
    {
      throw StoreError.invalidSample
    }
    if !allowSynthetic, revision.kind == "workout",
      let workout = try? JSONDecoder().decode(Workout.self, from: revision.payload),
      workout.origin == .synthetic
    {
      throw StoreError.invalidSample
    }
    if !allowSynthetic, revision.kind == "detectedActivity",
      let decision = try? JSONDecoder().decode(
        DetectedActivityDecision.self, from: revision.payload),
      decision.candidate.origin == .synthetic
    {
      throw StoreError.invalidSample
    }
  }
  public func saveRevision(
    _ revision: Revision, enqueue: Bool = true, expectedParentIDs: [UUID]? = nil
  ) throws {
    try validateRevision(revision)
    let data = try JSONEncoder().encode(revision)
    try transaction {
      if let expectedParentIDs {
        guard
          Set(try revisionHeads(entityID: revision.entityID).map(\.id)) == Set(expectedParentIDs)
        else { throw StoreError.conflictingObservation }
      }
      if let old = try rows(
        "SELECT payload FROM revisions WHERE id=?", [.text(revision.id.uuidString)]
      ).first {
        guard try JSONDecoder().decode(Revision.self, from: old) == revision else {
          throw StoreError.conflictingObservation
        }
        return
      }
      try run(
        "INSERT INTO revisions VALUES(?,?,?,?)",
        [
          .text(revision.id.uuidString), .text(revision.entityID.uuidString), .text(revision.kind),
          .blob(data),
        ])
      if enqueue {
        try queue(
          SyncEnvelope(id: "revision-\(revision.id.uuidString)", kind: "revision", payload: data))
      }
    }
  }
  public func revisions(kind: String? = nil) throws -> [Revision] {
    let r = try rows(
      kind == nil ? "SELECT payload FROM revisions" : "SELECT payload FROM revisions WHERE kind=?",
      kind.map { [.text($0)] } ?? [])
    return try r.map { try JSONDecoder().decode(Revision.self, from: $0) }
  }
  public func revisionHeads(entityID: UUID) throws -> [Revision] {
    let all = try rows("SELECT payload FROM revisions WHERE entity=?", [.text(entityID.uuidString)])
      .map { try JSONDecoder().decode(Revision.self, from: $0) }
    let parents = Set(all.flatMap(\.parentIDs))
    return all.filter { !parents.contains($0.id) }
  }
  public func metadata(_ key: String) throws -> Data? {
    try rows("SELECT value FROM metadata WHERE key=?", [.text(key)]).first
  }
  public func setMetadata(_ key: String, value: Data) throws {
    try run("INSERT OR REPLACE INTO metadata VALUES(?,?)", [.text(key), .blob(value)])
  }
  public func pending(now: Date = Date()) throws -> [PendingChange] {
    let s = try prepare(
      "SELECT id,kind,payload,attempts,next FROM outbox WHERE next<=? LIMIT 100",
      [.number(now.timeIntervalSince1970)])
    defer { sqlite3_finalize(s) }
    var result: [PendingChange] = []
    while sqlite3_step(s) == SQLITE_ROW {
      let id = String(cString: sqlite3_column_text(s, 0))
      let kind = String(cString: sqlite3_column_text(s, 1))
      let count = Int(sqlite3_column_bytes(s, 2))
      let data = Data(bytes: sqlite3_column_blob(s, 2), count: count)
      result.append(
        PendingChange(
          id: id, attempts: Int(sqlite3_column_int(s, 3)),
          nextAttempt: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)),
          envelope: SyncEnvelope(id: id, kind: kind, payload: data)))
    }
    return result
  }
  public func pendingCount() throws -> Int {
    let s = try prepare("SELECT COUNT(*) FROM outbox", [])
    defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int(s, 0))
  }
  public func acknowledge(_ id: String, expectedPayload: Data? = nil) throws {
    if let expectedPayload {
      try run("DELETE FROM outbox WHERE id=? AND payload=?", [.text(id), .blob(expectedPayload)])
    } else {
      try run("DELETE FROM outbox WHERE id=?", [.text(id)])
    }
  }
  public func resetRetrySchedule() throws { try run("UPDATE outbox SET next=0") }
  public func deferChange(_ id: String, attempt: Int, retryAfter: Double? = nil) throws {
    let delay = retryAfter ?? min(21600, pow(2, Double(min(attempt, 12))) * 5)
    try run(
      "UPDATE outbox SET attempts=?,next=? WHERE id=?",
      [.number(Double(attempt)), .number(Date().timeIntervalSince1970 + delay), .text(id)])
  }
  public func materialize(_ envelope: SyncEnvelope) throws -> SyncEnvelope {
    guard envelope.kind == "batch" else { return envelope }
    guard let text = String(data: envelope.payload, encoding: .utf8) else {
      throw StoreError.invalidArchive
    }
    let parts = text.split(separator: "|")
    guard parts.count >= 2, let device = UUID(uuidString: String(parts[0])),
      let bucket = Double(parts[1])
    else { throw StoreError.invalidArchive }
    let samples = try rows(
      "SELECT payload FROM observations WHERE time>=? AND time<? AND device=?",
      [.number(bucket * 900), .number((bucket + 1) * 900), .text(device.uuidString)]
    ).map { try JSONDecoder().decode(Measurement.self, from: $0) }.filter {
      $0.origin != .synthetic
    }
    return SyncEnvelope(id: envelope.id, kind: "batch", payload: try JSONEncoder().encode(samples))
  }
  public func apply(_ envelope: SyncEnvelope) throws {
    switch envelope.kind {
    case "batch":
      let m = try JSONDecoder().decode([Measurement].self, from: envelope.payload)
      try transaction {
        for s in m {
          guard s.origin != .synthetic else { throw StoreError.invalidSample }
          try insertOne(s, enqueue: false)
        }
      }
    case "revision":
      try saveRevision(JSONDecoder().decode(Revision.self, from: envelope.payload), enqueue: false)
    default: throw StoreError.invalidArchive
    }
  }
  public func requeueAll() throws {
    try transaction {
      for data in try rows("SELECT payload FROM observations") {
        let m = try JSONDecoder().decode(Measurement.self, from: data)
        if m.origin != .synthetic {
          let bucket = Int(floor(m.timestamp.timeIntervalSince1970 / 900))
          try queue(
            SyncEnvelope(
              id: "batch-\(m.deviceID.uuidString)-\(bucket)", kind: "batch",
              payload: Data("\(m.deviceID.uuidString)|\(bucket)|\(UUID().uuidString)".utf8)))
        }
      }
      for r in try revisions() {
        try queue(
          SyncEnvelope(
            id: "revision-\(r.id.uuidString)", kind: "revision",
            payload: try JSONEncoder().encode(r)))
      }
    }
  }
  public func exportArchive() throws -> BackupArchive {
    let content = ArchivePayload(
      measurements: try rows("SELECT payload FROM observations").map {
        try JSONDecoder().decode(Measurement.self, from: $0)
      }, revisions: try revisions())
    return BackupArchive(payload: try JSONEncoder().encode(content))
  }
  public func importArchive(_ archive: BackupArchive) throws {
    try archive.validate()
    let content = try JSONDecoder().decode(ArchivePayload.self, from: archive.payload)
    guard !content.measurements.contains(where: { $0.origin == .synthetic }) else {
      throw StoreError.invalidArchive
    }
    // Validate every row before beginning; all rows and outbox entries commit atomically.
    try transaction {
      for m in content.measurements { try insertOne(m, enqueue: true) }
      for r in content.revisions {
        try validateRevision(r)
        let data = try JSONEncoder().encode(r)
        if let old = try rows("SELECT payload FROM revisions WHERE id=?", [.text(r.id.uuidString)])
          .first
        {
          guard try JSONDecoder().decode(Revision.self, from: old) == r else {
            throw StoreError.conflictingObservation
          }
          continue
        }
        try run(
          "INSERT INTO revisions VALUES(?,?,?,?)",
          [.text(r.id.uuidString), .text(r.entityID.uuidString), .text(r.kind), .blob(data)])
        try queue(SyncEnvelope(id: "revision-\(r.id.uuidString)", kind: "revision", payload: data))
      }
    }
  }
}
private enum SQLValue {
  case text(String)
  case number(Double)
  case blob(Data)
}
private struct ArchivePayload: Codable {
  var measurements: [Measurement]
  var revisions: [Revision]
}
