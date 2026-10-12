import ActivityKit
import Foundation

struct TempoActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var startedAt: Date
    var elapsed: Double
    var heartRate: Int?
    var paused: Bool
    var updatedAt: Date
    var source: String
  }
  var workoutID: String
  var activity: String
}
