import SwiftUI

struct WelcomeView: View {
    let start: () -> Void

    private let points: [(String, String, String)] = [
        ("speaker.wave.3.fill", "A volume for every app", "Turn Safari down while the music plays, or silence a noisy tab for good."),
        ("slider.vertical.3", "An equalizer for each one", "Warm up a podcast, lift a voice, or tame the bass, app by app."),
        ("hifispeaker.2.fill", "Choose where each app plays", "Music to the speakers, a call to your headphones, at the same time."),
    ]

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                Text("Welcome to Levels").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("The sound of your Mac, one app at a time.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(points, id: \.1) { p in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: p.0).font(.system(size: 20))
                            .foregroundStyle(Color.accentColor).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.1).font(.system(size: 13, weight: .semibold))
                            Text(p.2).font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            VStack(spacing: 6) {
                Label("macOS will ask once for permission to hear app audio.", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("You will find Levels in the menu bar at the top of your screen.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button(action: start) {
                Text("Get Started").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 440)
    }
}
