import Foundation

/// Publication of a daily widget summary, not a live sensor display.
public struct WidgetPublicationPolicy: Sendable {
  private struct Contents: Equatable, Sendable {
    let readiness: Int?
    let sleepSeconds: Double?
    let privateDetails: Bool
  }
  private var contents: Contents?
  private var publishedAt: Date?
  public init() {}
  public mutating func shouldPublish(readiness: Int?, sleepSeconds: Double?, privateDetails: Bool,
    now: Date, force: Bool = false) -> Bool {
    guard now.timeIntervalSince1970.isFinite else { return false }
    let next = Contents(readiness: readiness,
      sleepSeconds: sleepSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
      privateDetails: privateDetails)
    guard force || next != contents || publishedAt.map({
      now < $0 || now.timeIntervalSince($0) >= 1800
    }) ?? true else { return false }
    contents = next
    publishedAt = now
    return true
  }
}
