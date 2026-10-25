import Foundation
import AppKit

// Which apps are rows, which are folded away. Run with run_tests.sh (compiles all Engine + Model sources).
var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print(ok ? "PASS" : "FAIL", name, ok ? "" : detail)
    if !ok { failures += 1 }
}

func row(_ id: String, _ name: String, playing: Bool, _ s: AppSettings = AppSettings()) -> MixerApp {
    MixerApp(app: AudioApp(bundleID: id, name: name, icon: nil, processIDs: [], isPlaying: playing), settings: s)
}
var zero = AppSettings(); zero.volume = 0
var boost = AppSettings(); boost.volume = 1.5
var low = AppSettings(); low.volume = 0.21
var muted = AppSettings(); muted.muted = true
var eq = AppSettings(); eq.eq = [4, 3, 1, 0, -1, 0, 1, 3, 4, 3]
let names: ([MixerApp]) -> [String] = { $0.map(\.app.name) }

// The user's real situation: Brave 0%, FaceTime & Calls 150%, Music 21%, all silent; Stalker Player playing.
let real = [
    row("com.brave.Browser", "Brave Browser", playing: false, zero),
    row("system.calls", "FaceTime & Calls", playing: false, boost),
    row("com.apple.Music", "Music", playing: false, low),
    row("com.nurik.stalkerplayer", "Stalker Player", playing: true),
    row("com.apple.MobileSMS", "Messages", playing: false),
]
var live = Visibility.live(real, lastSound: [:], now: 1000)
check("only the app making sound is in the panel", names(live) == ["Stalker Player"], names(live).description)
check("not playing means not there, saved changes or not",
      !names(live).contains("Brave Browser") && !names(live).contains("FaceTime & Calls")
      && !names(live).contains("Music") && !names(live).contains("Messages"))
live = Visibility.live(real.filter { $0.id != "com.nurik.stalkerplayer" }, lastSound: [:], now: 1000)
check("nothing playing: the panel list is empty", live.isEmpty, names(live).description)

// Grace: an app that just stopped stays a row for a moment, then leaves.
let justStopped = [row("a", "Spotify", playing: false), row("b", "Safari", playing: true)]
live = Visibility.live(justStopped, lastSound: ["a": 998], now: 1000)
check("stopped 2 s ago: still a row (no flicker between songs)", names(live) == ["Safari", "Spotify"], names(live).description)
live = Visibility.live(justStopped, lastSound: ["a": 990], now: 1000)
check("stopped 10 s ago: gone", names(live) == ["Safari"], names(live).description)

// A silenced app that plays is a row again, so it can always be adjusted when it matters.
live = Visibility.live([row("a", "Brave Browser", playing: true, zero)], lastSound: [:], now: 1000)
check("Brave at 0% comes back the moment it plays", names(live) == ["Brave Browser"])

// Order: playing first, then name.
let order = [row("1", "Zoom", playing: true), row("2", "Arc", playing: true), row("3", "Mail", playing: false)]
live = Visibility.live(order, lastSound: ["3": 999], now: 1000)
check("playing first, then by name", names(live) == ["Arc", "Zoom", "Mail"], names(live).description)

// Summaries are plain language and cover every kind of change.
check("summary volume 0", zero.summary == "Volume 0%", zero.summary)
check("summary boost", boost.summary == "Boost 150%", boost.summary)
check("summary low", low.summary == "Volume 21%", low.summary)
check("summary muted wins over volume", muted.summary == "Muted", muted.summary)
var all = eq; all.volume = 0.5; all.outputUID = "x"
check("summary lists everything", all.summary == "Volume 50% · Equalizer · Own output", all.summary)
check("untouched has no summary", AppSettings().summary == "" && !AppSettings().needsProcessing)
check("volume 0 counts as silenced", zero.isSilenced && muted.isSilenced && !low.isSilenced)

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
