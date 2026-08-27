import SwiftUI
import WidgetKit

/// Entry point of the extension. A bundle can hold several widgets; this one
/// carries only the Live Activity, since the demo has no Home Screen widget.
@main
struct DeliveryWidgetBundle: WidgetBundle {
  var body: some Widget {
    DeliveryLiveActivity()
  }
}
