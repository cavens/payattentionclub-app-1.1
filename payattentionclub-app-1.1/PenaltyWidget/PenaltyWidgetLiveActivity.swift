//
//  PenaltyWidgetLiveActivity.swift
//  PenaltyWidget
//
//  Created by Jef Cavens on 27/01/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct PenaltyWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct PenaltyWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PenaltyWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension PenaltyWidgetAttributes {
    fileprivate static var preview: PenaltyWidgetAttributes {
        PenaltyWidgetAttributes(name: "World")
    }
}

extension PenaltyWidgetAttributes.ContentState {
    fileprivate static var smiley: PenaltyWidgetAttributes.ContentState {
        PenaltyWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: PenaltyWidgetAttributes.ContentState {
         PenaltyWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: PenaltyWidgetAttributes.preview) {
   PenaltyWidgetLiveActivity()
} contentStates: {
    PenaltyWidgetAttributes.ContentState.smiley
    PenaltyWidgetAttributes.ContentState.starEyes
}
