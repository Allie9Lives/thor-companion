import WidgetKit
import SwiftUI
import ActivityKit

struct BatteryEntry: TimelineEntry {
  let date: Date
  let snapshot: BatterySnapshot?
}

struct BatteryProvider: TimelineProvider {
  func placeholder(in context: Context) -> BatteryEntry {
    BatteryEntry(date: .now, snapshot: BatterySnapshot(percent: 69, updatedAt: .now, charging: false, connected: true))
  }
  func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : BatteryEntry(date: .now, snapshot: BatteryStore.read()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
    let now = Date(), value = BatteryStore.read()
    var entries = [BatteryEntry(date: now, snapshot: value)]
    if let value, value.connected {
      let expires = value.updatedAt.addingTimeInterval(91)
      if expires > now { entries.append(BatteryEntry(date: expires, snapshot: value)) }
    }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
  }
}

// Use the actual level even while charging; the plug is a separate symbol.
struct BatteryStatusIcon: View {
  let snapshot: BatterySnapshot?
  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: snapshot?.levelSymbol ?? "battery.0")
      if snapshot?.charging == true {
        Image(systemName: "powerplug.fill").imageScale(.small)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(snapshot.map { "Battery \($0.percent) percent. \($0.charging ? "Charging." : "")" } ?? "Battery reading unavailable")
  }
}

struct ThorDeviceMark: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.56), cornerSize: CGSize(width: 4, height: 4))
    path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + rect.height * 0.66, width: rect.width, height: rect.height * 0.34), cornerSize: CGSize(width: 3, height: 3))
    return path
  }
}

struct HomeBatteryView: View {
  let entry: BatteryEntry
  private var value: BatterySnapshot? { entry.snapshot }
  private var fresh: Bool { value?.isFresh(at: entry.date) ?? false }
  private var tint: Color {
    guard let value else { return .secondary }
    return value.percent <= 20 && !value.charging ? .red : .green
  }
  var body: some View {
    GeometryReader { geometry in
      let diameter = min(100, max(44, min(geometry.size.width - 8, geometry.size.height - 50)))
      VStack(spacing: 4) {
        ZStack {
          Circle().stroke(Color.primary.opacity(0.12), lineWidth: 8)
          if let value {
            Circle().trim(from: 0, to: value.fraction)
              .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
              .rotationEffect(.degrees(-90))
          }
          ThorDeviceMark().stroke(Color.primary, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            .frame(width: diameter * 0.38, height: diameter * 0.44)
        }
        .padding(4)
        .frame(width: diameter, height: diameter)
        HStack(spacing: 5) {
          Text(value.map { "\($0.percent)%" } ?? "—")
            .font(.system(size: 23, weight: .semibold, design: .rounded))
          if value?.charging == true {
            Image(systemName: "powerplug.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
          }
        }
        .minimumScaleFactor(0.7).lineLimit(1)
        Text(value == nil ? "Open Thor Companion" : fresh ? "Thor" : "Thor · last known")
          .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(value.map { "Thor battery \($0.percent) percent. \($0.charging ? "Charging." : "") \(fresh ? "Recent reading." : "Last known reading.")" } ?? "Open Thor Companion to receive a battery reading.")
  }
}

struct RectangularBatteryView: View {
  let entry: BatteryEntry
  private var value: BatterySnapshot? { entry.snapshot }
  var body: some View {
    GeometryReader { box in
      HStack(spacing: 6) {
        BatteryStatusIcon(snapshot: value)
          .font(.system(size: min(20, box.size.height * 0.4)))
          .frame(width: value?.charging == true ? 56 : 32)
        VStack(alignment: .leading, spacing: 2) {
          Text(value.map { "Thor  \($0.percent)%" } ?? "Thor")
            .font(.system(size: min(16, box.size.height * 0.3), weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.75)
          if let value {
            Text("As of \(value.updatedAt.formatted(date: .omitted, time: .shortened))")
              .font(.system(size: min(12, box.size.height * 0.23)))
              .lineLimit(1).minimumScaleFactor(0.75)
          } else {
            Text("Open app")
              .font(.system(size: min(12, box.size.height * 0.23)))
              .lineLimit(1)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(value.map { "Thor battery \($0.percent) percent. \($0.charging ? "Charging." : "")" } ?? "Open Thor Companion and connect to receive a battery reading.")
  }
}

struct BatteryWidgetView: View {
  let entry: BatteryEntry
  @Environment(\.widgetFamily) private var family
  private var value: BatterySnapshot? { entry.snapshot }
  private var fresh: Bool { value?.isFresh(at: entry.date) ?? false }
  private var percent: String { value.map { "\($0.percent)%" } ?? "—" }

  @ViewBuilder var body: some View {
    switch family {
    case .systemSmall:
      HomeBatteryView(entry: entry)
    case .accessoryCircular:
      Gauge(value: Double(value?.percent ?? 0), in: 0...100) {
        EmptyView()
      } currentValueLabel: {
        VStack(spacing: 0) {
          Text(value == nil ? "—" : "\(value!.percent)").font(.system(.title3, design: .rounded).bold())
          BatteryStatusIcon(snapshot: value).font(.system(size: 10))
        }
      }
      .gaugeStyle(.accessoryCircular)
      .accessibilityLabel("Thor battery \(percent). \(value?.charging == true ? "Charging. " : "")\(fresh ? "Recent reading" : "Last known reading")")
    case .accessoryInline:
      HStack(spacing: 4) {
        BatteryStatusIcon(snapshot: value)
        Text(value == nil ? "Thor · Open app" : "Thor \(percent)\(fresh ? "" : " · last known")")
      }
    default:
      RectangularBatteryView(entry: entry)
    }
  }
}

struct BatteryWidgetContainer: View {
  let entry: BatteryEntry
  @Environment(\.widgetFamily) private var family
  var body: some View {
    if #available(iOSApplicationExtension 17.0, *) {
      BatteryWidgetView(entry: entry)
        .containerBackground(for: .widget) {
          if family == .systemSmall { Color(.systemBackground) }
        }
    } else {
      BatteryWidgetView(entry: entry)
    }
  }
}

struct ThorBatteryWidget: Widget {
  let kind = "ThorBattery"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: BatteryProvider()) { entry in
      BatteryWidgetContainer(entry: entry)
    }
    .configurationDisplayName("Thor Battery")
    .description("The latest battery reading received from your AYN Thor.")
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}


@available(iOSApplicationExtension 16.2, *)
struct ThorLiveBatteryWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ThorBatteryAttributes.self) { context in
      HStack(spacing: 14) {
        BatteryStatusIcon(snapshot: context.state)
          .font(.title)
        VStack(alignment: .leading, spacing: 4) {
          Text("Thor Battery").font(.headline)
          if context.isStale || !context.state.connected {
            Text("Last known reading").font(.caption).foregroundStyle(.secondary)
          } else {
            HStack(spacing: 4) {
              Text("Updated")
              Text(context.state.updatedAt, style: .relative)
            }.font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        Text("\(context.state.percent)%")
          .font(.system(.largeTitle, design: .rounded).weight(.medium))
      }
      .padding(20)
      .activityBackgroundTint(Color(.secondarySystemBackground))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 4) {
            BatteryStatusIcon(snapshot: context.state)
            Text("Thor")
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("\(context.state.percent)%").font(.title2)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if context.isStale || !context.state.connected {
            Text("Last known reading")
          } else {
            HStack(spacing: 4) {
              Text("Updated")
              Text(context.state.updatedAt, style: .relative)
            }
          }
        }
      } compactLeading: {
        BatteryStatusIcon(snapshot: context.state)
      } compactTrailing: {
        Text("\(context.state.percent)%").font(.caption)
      } minimal: {
        Text("\(context.state.percent)%").font(.caption2)
      }
    }
  }
}

@main
struct ThorBatteryBundle: WidgetBundle {
  var body: some Widget {
    ThorBatteryWidget()
    if #available(iOSApplicationExtension 16.2, *) {
      ThorLiveBatteryWidget()
    }
  }
}
