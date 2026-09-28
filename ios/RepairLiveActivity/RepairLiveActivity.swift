// ios/RepairLiveActivity/RepairLiveActivity.swift

import ActivityKit
import WidgetKit
import SwiftUI

public struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryStatus = ContentState

    public struct ContentState: Codable, Hashable {
        public var remainingMinutes: Int
        public var statusText: String
        public var providerName: String
    }

    public var id = UUID()
}

@main
struct RepairLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RepairLiveActivity()
    }
}

struct RepairLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            // Kilit Ekranı ve Bildirim Çekmecesi Görünümü
            HStack(spacing: 16) {
                Image("logo2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .padding(8)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.providerName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(context.state.statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(context.state.remainingMinutes)")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.64))
                    Text("dakika")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(16)
            .background(Color(red: 0.02, green: 0.02, blue: 0.03))
            .activityBackgroundTint(Color(red: 0.02, green: 0.02, blue: 0.03))

        } dynamicIsland: { context in
            DynamicIsland {
                // Dynamic Island'a Uzun Basılınca Açılan Genişletilmiş Görünüm
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image("logo2")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.providerName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(context.state.statusText)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 8)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(context.state.remainingMinutes)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.64))
                        Text("dk")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.64))
                        ProgressView(value: 0.7)
                            .tint(Color(red: 0.0, green: 1.0, blue: 0.64))
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Sol Bölüm: logo2.png
                Image("logo2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .padding(.leading, 4)
            } compactTrailing: {
                // Sağ Bölüm: Dakika Sayacı
                Text("\(context.state.remainingMinutes)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.trailing, 4)
            } minimal: {
                Image("logo2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            }
        }
    }
}