// ios/RepairLiveActivity/RepairLiveActivity.swift

import ActivityKit
import WidgetKit
import SwiftUI

public struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryStatus = ContentState

    public struct ContentState: Codable, Hashable {
        public var activityType: String?       // "job_alert", "offer_tracking", "provider_tracking"
        public var title: String?              // İş başlığı veya müşteri adı
        public var subtitle: String?           // Mesafe, teklif tutarı veya ek bilgi
        public var statusText: String?         // Durum açıklaması
        public var remainingMinutes: Int?      // Kalan dakika (usta takip)
        public var remainingSeconds: Int?      // Kalan kabul süresi (yeni iş)
        public var providerName: String?       // Usta adı
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
                    Text(context.state.title ?? context.state.providerName ?? "OtoTag")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(context.state.statusText ?? "İşlem devam ediyor")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let seconds = context.state.remainingSeconds {
                        Text("\(seconds)")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(.orange)
                        Text("saniye")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    } else if let minutes = context.state.remainingMinutes {
                        Text("\(minutes)")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.64))
                        Text("dakika")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    } else if let sub = context.state.subtitle {
                        Text(sub)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
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
                            Text(context.state.title ?? context.state.providerName ?? "OtoTag")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(context.state.statusText ?? "")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 8)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        if let seconds = context.state.remainingSeconds {
                            Text("\(seconds)")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(.orange)
                            Text("sn")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                        } else if let minutes = context.state.remainingMinutes {
                            Text("\(minutes)")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.64))
                            Text("dk")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        if context.state.activityType == "job_alert" {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                        } else if context.state.activityType == "offer_tracking" {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                        } else {
                            Image(systemName: "car.fill")
                                .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.64))
                                .font(.system(size: 12))
                        }
                        
                        if let sub = context.state.subtitle {
                            Text(sub)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            ProgressView(value: 0.7)
                                .tint(context.state.activityType == "job_alert" ? .orange : Color(red: 0.0, green: 1.0, blue: 0.64))
                        }
                        
                        Spacer()
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
                // Sağ Bölüm: Dakika, Saniye veya Onay İkonu
                if let seconds = context.state.remainingSeconds {
                    Text("\(seconds)s")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.trailing, 4)
                } else if let minutes = context.state.remainingMinutes {
                    Text("\(minutes)m")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.trailing, 4)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 13))
                        .padding(.trailing, 4)
                }
            } minimal: {
                Image("logo2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            }
        }
    }
}