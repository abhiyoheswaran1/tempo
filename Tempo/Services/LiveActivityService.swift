import ActivityKit
import Foundation

@MainActor final class LiveActivityService {
  nonisolated func update(
    workoutID: String, name: String, state: TempoActivityAttributes.ContentState
  ) async {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let activity = Activity<TempoActivityAttributes>.activities.first {
      $0.attributes.workoutID == workoutID
    }
    let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))
    if let activity {
      await activity.update(content)
    } else {
      _ = try? Activity.request(
        attributes: TempoActivityAttributes(workoutID: workoutID, activity: name), content: content,
        pushType: nil)
    }
  }
  nonisolated func end() async {
    for a in Activity<TempoActivityAttributes>.activities {
      await a.end(nil, dismissalPolicy: .immediate)
    }
  }
}
