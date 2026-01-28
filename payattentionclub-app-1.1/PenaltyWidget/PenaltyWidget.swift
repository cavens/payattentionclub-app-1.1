//
//  PenaltyWidget.swift
//  PenaltyWidget
//

import WidgetKit
import SwiftUI

private let appGroupIdentifier = "group.com.payattentionclub2.0.app"
private let widgetPenaltyKey = "widgetCurrentPenalty"

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PenaltyEntry {
        PenaltyEntry(date: Date(), penalty: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (PenaltyEntry) -> Void) {
        let entry = PenaltyEntry(date: Date(), penalty: penaltyFromAppGroup())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PenaltyEntry>) -> Void) {
        let penalty = penaltyFromAppGroup()
        let entry = PenaltyEntry(date: Date(), penalty: penalty)
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
        completion(timeline)
    }

    private func penaltyFromAppGroup() -> Double {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return 0 }
        guard userDefaults.object(forKey: widgetPenaltyKey) != nil else { return 0 }
        return userDefaults.double(forKey: widgetPenaltyKey)
    }
}

struct PenaltyEntry: TimelineEntry {
    let date: Date
    let penalty: Double
}

private let widgetPink = Color(red: 226/255, green: 204/255, blue: 205/255)

struct PenaltyWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .center, spacing: 0) {
                Image("PayAttentionClubLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width * 0.5)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                Text(String(format: "$%.2f", entry.penalty))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.black)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PenaltyWidget: Widget {
    let kind: String = "PenaltyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                PenaltyWidgetEntryView(entry: entry)
                    .containerBackground(widgetPink, for: .widget)
            } else {
                PenaltyWidgetEntryView(entry: entry)
                    .padding()
                    .background(widgetPink)
            }
        }
        .configurationDisplayName("Current Penalty")
        .description("Shows your current penalty amount.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    PenaltyWidget()
} timeline: {
    PenaltyEntry(date: .now, penalty: 12.50)
}
