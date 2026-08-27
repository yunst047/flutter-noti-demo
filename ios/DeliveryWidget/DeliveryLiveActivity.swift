import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen / banner presentation.
struct DeliveryLockScreenView: View {
  let snapshot: DeliverySnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(snapshot.orderId, systemImage: "shippingbox.fill")
          .font(.headline)
        Spacer()
        Text(snapshot.eta)
          .font(.headline.monospacedDigit())
          .foregroundStyle(.tint)
      }

      Text(snapshot.stage.label)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      DeliveryStageBar(stage: snapshot.stage)

      if !snapshot.rider.isEmpty {
        Label(snapshot.rider, systemImage: "person.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    // Lock Screen cards are drawn by the system in its own colour scheme, so the
    // background has to be declared rather than inherited.
    .activityBackgroundTint(Color.black.opacity(0.35))
    .activitySystemActionForegroundColor(.white)
  }
}

/// Four segments rather than a continuous bar, to match the Android
/// `ProgressStyle` segments this demo shows alongside it.
struct DeliveryStageBar: View {
  let stage: DeliveryStage

  var body: some View {
    HStack(spacing: 4) {
      ForEach(DeliveryStage.allCases, id: \.rawValue) { s in
        Capsule()
          .fill(s.rawValue <= stage.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
          .frame(height: 6)
      }
    }
  }
}

struct DeliveryLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      DeliveryLockScreenView(snapshot: DeliverySnapshot(context.attributes))
    } dynamicIsland: { context in
      let snapshot = DeliverySnapshot(context.attributes)

      return DynamicIsland {
        // Expanded — shown while the island is long-pressed.
        DynamicIslandExpandedRegion(.leading) {
          Label {
            Text(snapshot.orderId).font(.caption)
          } icon: {
            Image(systemName: "shippingbox.fill")
          }
          .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(snapshot.eta)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tint)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.stage.label).font(.footnote)
            DeliveryStageBar(stage: snapshot.stage)
          }
          .padding(.horizontal, 4)
        }
      } compactLeading: {
        Image(systemName: snapshot.stage.symbol)
          .foregroundStyle(.tint)
      } compactTrailing: {
        Text(snapshot.eta)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.tint)
      } minimal: {
        // Shown when another activity is competing for the island.
        Image(systemName: snapshot.stage.symbol)
          .foregroundStyle(.tint)
      }
      .keylineTint(.orange)
    }
  }
}
