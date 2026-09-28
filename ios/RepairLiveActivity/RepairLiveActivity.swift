// ios/RepairLiveActivity/RepairLiveActivity.swift

import ActivityKit
import WidgetKit
import SwiftUI

public struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    // Paket için bu satır zorunludur:
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable { }

    public var id = UUID()
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}

let sharedDefault = UserDefaults(suiteName: "group.com.ototag.app")

@main
struct RepairLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RepairLiveActivity()
    }
}

struct RepairLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            // Flutter'dan gelen verileri App Group'tan çekiyoruz
            let title = sharedDefault?.string(forKey: context.attributes.prefixedKey("title")) ?? "OTOTAG"
            let subtitle = sharedDefault?.string(forKey: context.attributes.prefixedKey("subtitle"))
            let statusText = sharedDefault?.string(forKey: context.attributes.prefixedKey("statusText")) ?? "İşlem devam ediyor"
            let remainingSeconds = sharedDefault?.integer(forKey: context.attributes.prefixedKey("remainingSeconds")) ?? 0
            let remainingMinutes = sharedDefault?.integer(forKey: context.attributes.prefixedKey("remainingMinutes")) ?? 0
            let activityType = sharedDefault?.string(forKey: context.attributes.prefixedKey("activityType")) ?? ""

            // Kilit Ekranı ve Bildirim Çekmecesi Görünümü
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: activityType == "job_alert" ? "wrench.and.screwdriver.fill" : "car.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 20))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if remainingSeconds > 0 {
                        Text("\(remainingSeconds)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(.orange)
                        Text("saniye")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    } else if remainingMinutes > 0 {
                        Text("\(remainingMinutes)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.64))
                        Text("dakika")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    } else if let sub = subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(16)
            .background(Color(red: 0.06, green: 0.06, blue: 0.07))
            .activityBackgroundTint(Color(red: 0.06, green: 0.06, blue: 0.07))

        } dynamicIsland: { context in
            let title = sharedDefault?.string(forKey: context.attributes.prefixedKey("title")) ?? "OTOTAG"
            let subtitle = sharedDefault?.string(forKey: context.attributes.prefixedKey("subtitle")) ?? ""
            let statusText = sharedDefault?.string(forKey: context.attributes.prefixedKey("statusText")) ?? ""
            let remainingSeconds = sharedDefault?.integer(forKey: context.attributes.prefixedKey("remainingSeconds")) ?? 0
            let remainingMinutes = sharedDefault?.integer(forKey: context.attributes.prefixedKey("remainingMinutes")) ?? 0
            let activityType = sharedDefault?.string(forKey: context.attributes.prefixedKey("activityType")) ?? ""

            return DynamicIsland {
                // Ada Genişletilmiş Durum (Uzun basınca)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: activityType == "job_alert" ? "wrench.and.screwdriver.fill" : "car.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(statusText)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 8)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        if remainingSeconds > 0 {
                            Text("\(remainingSeconds) sn")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(.orange)
                        } else if remainingMinutes > 0 {
                            Text("\(remainingMinutes) dk")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.64))
                        } else if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Image(systemName: activityType == "job_alert" ? "bell.fill" : "car.fill")
                            .foregroundColor(activityType == "job_alert" ? .orange : Color(red: 0.0, green: 1.0, blue: 0.64))
                            .font(.system(size: 12))

                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Ada Küçük Sol Simge
                Image(systemName: activityType == "job_alert" ? "wrench.fill" : "car.fill")
                    .foregroundColor(.orange)
                    .padding(.leading, 4)
            } compactTrailing: {
                // Ada Küçük Sağ Bilgi
                if remainingSeconds > 0 {
                    Text("\(remainingSeconds)s")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.trailing, 4)
                } else if remainingMinutes > 0 {
                    Text("\(remainingMinutes)m")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.64))
                        .padding(.trailing, 4)
                } else if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.trailing, 4)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                        .padding(.trailing, 4)
                }
            } minimal: {
                Image(systemName: activityType == "job_alert" ? "wrench.fill" : "car.fill")
                    .foregroundColor(.orange)
            }
        }
    }
}