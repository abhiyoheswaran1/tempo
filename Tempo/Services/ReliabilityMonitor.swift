import Foundation
import MetricKit
import Observation
import TempoCore

/// Phone-local, opt-in system reports. No sensor payloads, backend or cloud upload.
@MainActor @Observable final class ReliabilityMonitor: NSObject, MXMetricManagerSubscriber {
  private(set) var enabled: Bool
  private(set) var archive = ReliabilityArchive()
  private(set) var error: String?
  private var demo = ProcessInfo.processInfo.arguments.contains("--demo")
  private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
  private var subscribed = false
  private let preference = "tempo.reliability.enabled"
  private var file: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Tempo/reliability-reports.json")
  }
  override init() {
    enabled = UserDefaults.standard.bool(forKey: "tempo.reliability.enabled")
    super.init()
    if !testing, let data = boundedArchiveData(),
      let stored = try? JSONDecoder().decode(ReliabilityArchive.self, from: data) {
      for report in stored.reports { archive.record(report) }
    }
    updateSubscription()
  }
  private func boundedArchiveData() -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 65537), data.count <= 65536 else { return nil }
    return data
  }
  func setEnabled(_ value: Bool) {
    guard !demo, !testing else { return }
    enabled = value; UserDefaults.standard.set(value, forKey: preference)
    updateSubscription()
  }
  func setDemo(_ value: Bool) { demo = value; updateSubscription() }
  private func updateSubscription() {
    let wanted = enabled && !demo && !testing
    if wanted && !subscribed { MXMetricManager.shared.add(self); subscribed = true }
    else if !wanted && subscribed { MXMetricManager.shared.remove(self); subscribed = false }
  }
  nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
    let reports = payloads.prefix(7).map { payload in
      ReliabilityReport(start: payload.timeStampBegin, end: payload.timeStampEnd,
        cpuSeconds: payload.cpuMetrics?.cumulativeCPUTime.converted(to: .seconds).value,
        peakMemoryMB: payload.memoryMetrics?.peakMemoryUsage.converted(to: .megabytes).value,
        backgroundCPUExits: payload.applicationExitMetrics.flatMap {
          Int(exactly: $0.backgroundExitData.cumulativeCPUResourceLimitExitCount)
        }, appVersion: payload.latestApplicationVersion,
        includesMultipleVersions: payload.includesMultipleApplicationVersions)
    }
    Task { @MainActor [weak self] in
      guard let self, self.enabled, !self.demo, !self.testing else { return }
      for report in reports { self.archive.record(report) }
      self.persist()
    }
  }
  func clear() { archive.clear(); persist() }
  private func persist() {
    do {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
      let data = try JSONEncoder().encode(archive)
      guard data.count <= 65536 else { error = "System report archive exceeds its local limit."; return }
      try data.write(to: file,
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      error = nil
    } catch { self.error = "System reports could not save on this iPhone. Try again after unlocking." }
  }
}
