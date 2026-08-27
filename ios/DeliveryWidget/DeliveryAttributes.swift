import ActivityKit
import Foundation

/// The App Group both targets share.
///
/// The Live Activity's `ContentState` carries only this string — every field the
/// widget actually draws is written by the app into this suite's `UserDefaults`
/// and read back below. That is the `live_activities` plugin's data contract,
/// not a choice made here: ActivityKit needs the attributes type to be identical
/// on both sides, and the plugin cannot know the fields of an app it has never
/// seen. The App Group is what lets a *separate process* — the widget extension
/// — read what the app wrote.
let appGroupId = "group.com.f0h.flt-noti-demo"

let sharedDefault = UserDefaults(suiteName: appGroupId) ?? .standard

/// The name is load-bearing: it must be exactly `LiveActivitiesAppAttributes`.
///
/// ActivityKit matches an activity to a widget by the attributes *type*, and the
/// plugin requests activities using its own struct of that name. Rename this and
/// the activity is created successfully, reports itself as active, and simply
/// never appears on screen — with nothing logged to say why.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState

  public struct ContentState: Codable, Hashable {}

  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  /// Keys are namespaced per activity, so two concurrent deliveries do not read
  /// each other's values out of the shared suite.
  func prefixedKey(_ key: String) -> String {
    return "\(id)_\(key)"
  }
}

/// The four stages, mirroring the Android `ProgressStyle` segments exactly so the
/// two platforms can be watched side by side during a `Simulate Delivery` run.
enum DeliveryStage: Int, CaseIterable {
  case received = 0
  case preparing = 1
  case pickedUp = 2
  case onTheWay = 3

  var label: String {
    switch self {
    case .received: return "Order received"
    case .preparing: return "Restaurant is cooking"
    case .pickedUp: return "Rider picked it up"
    case .onTheWay: return "On the way to you"
    }
  }

  var symbol: String {
    switch self {
    case .received: return "checkmark.circle.fill"
    case .preparing: return "frying.pan.fill"
    case .pickedUp: return "bag.fill"
    case .onTheWay: return "bicycle"
    }
  }

  /// Fraction complete. Stage 0 is deliberately non-zero: a progress bar sitting
  /// at exactly 0 reads as "nothing is happening" rather than "just started".
  var progress: Double {
    Double(rawValue + 1) / Double(DeliveryStage.allCases.count)
  }
}

/// Everything the widget draws, resolved from the shared suite in one place.
///
/// Reading `UserDefaults` inline in the SwiftUI body would scatter string keys
/// through the view code and silently render blanks on a typo.
struct DeliverySnapshot {
  let orderId: String
  let stage: DeliveryStage
  let eta: String
  let rider: String

  init(_ attributes: LiveActivitiesAppAttributes) {
    orderId = sharedDefault.string(forKey: attributes.prefixedKey("orderId")) ?? "Order"
    eta = sharedDefault.string(forKey: attributes.prefixedKey("eta")) ?? "—"
    rider = sharedDefault.string(forKey: attributes.prefixedKey("rider")) ?? ""
    let raw = sharedDefault.integer(forKey: attributes.prefixedKey("stage"))
    stage = DeliveryStage(rawValue: raw) ?? .received
  }
}
