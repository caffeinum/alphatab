// escape hatch for apps without a dedicated hyperkey — the ⌘tab replacement.
//
// ⌘tab cycles most-recently-used, which means the order changes every time you
// use it and you can never build muscle memory. this cycles alphabetically
// instead: the same app is always the same number of presses away for a given
// set of running apps.
//
// runs as a resident daemon (see com.caffeinum.alphatab.plist) holding one panel
// that it shows and hides. skhd spawns a fresh process per keypress, so those
// processes do nothing but sigusr the daemon and exit — building a panel per
// press is what made it flash, and cold-starting one is what made it lag.
//
// usage: alphatab daemon
//        alphatab next|prev [--dry] [--hud-only]

import Cocoa

let launchedAt = Date()
let debug = ProcessInfo.processInfo.environment["ALPHATAB_DEBUG"] != nil
func mark(_ stage: String) {
    guard debug else { return }
    let ms = Date().timeIntervalSince(launchedAt) * 1000
    FileHandle.standardError.write(String(format: "%7.1fms  %@\n", ms, stage).data(using: .utf8)!)
}

let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? ""
guard ["daemon", "next", "prev"].contains(mode) else {
    FileHandle.standardError.write("usage: alphatab daemon | next|prev [--dry] [--hud-only]\n".data(using: .utf8)!)
    exit(1)
}
let dryRun = args.contains("--dry")
let hudOnly = args.contains("--hud-only")  // move the highlight without switching

let pidFile = (NSTemporaryDirectory() as NSString).appendingPathComponent("alphatab.pid")

func runningDaemon() -> pid_t? {
    guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
          let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
          pid != getpid(), kill(pid, 0) == 0
    else { return nil }
    return pid
}

// ── app list ────────────────────────────────────────────────────────────────
// the name on the .app, not localizedName — an app's bundle name can be
// something else entirely (Superconductor.app calls itself "super.engineering"),
// and the finder name is the one you actually recognise.
func displayName(_ a: NSRunningApplication) -> String {
    a.bundleURL?.deletingPathExtension().lastPathComponent ?? a.localizedName ?? "?"
}

// .regular == shows in the dock; drops menubar agents and background helpers
func dockApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }
        .sorted { displayName($0).lowercased() < displayName($1).lowercased() }
}

// each row also shows the app's own hyperkey, read straight out of skhdrc, so
// the escape hatch teaches you the direct shortcut instead of replacing it.
func shortcutsByBundleID() -> [String: String] {
    let path = ProcessInfo.processInfo.environment["ALPHATAB_SKHDRC"]
        ?? NSHomeDirectory() + "/.config/skhd/skhdrc"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
    var found: [String: [String]] = [:]

    for line in text.components(separatedBy: .newlines) {
        guard line.hasPrefix("ctrl + alt + shift + cmd - "),
              let colon = line.range(of: " : ") else { continue }
        var key = String(line[line.index(line.startIndex, offsetBy: 26)..<colon.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let command = String(line[colon.upperBound...])

        if key == "0x2C" { key = "/" }

        var bundleID: String?
        if let range = command.range(of: "open -b ") {
            bundleID = String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if command.contains("helium-raise") {
            bundleID = "net.imput.helium"
        }

        if let id = bundleID { found[id, default: []].append("⇪" + key.uppercased()) }
    }
    return found.mapValues { $0.joined(separator: " ") }
}

// ── one-shot modes ──────────────────────────────────────────────────────────
if dryRun {
    let apps = dockApps()
    let shortcuts = shortcutsByBundleID()
    let start = apps.firstIndex { $0.isActive } ?? 0
    let target = (start + (mode == "next" ? 1 : -1) + apps.count) % apps.count
    for (i, a) in apps.enumerated() {
        let flag = i == target ? "→" : (a.isActive ? "*" : " ")
        print("\(flag) \(displayName(a))\t\(a.bundleIdentifier.flatMap { shortcuts[$0] } ?? "")")
    }
    exit(0)
}

if mode != "daemon" {
    // the whole job of a keypress: poke the daemon and get out of the way
    if let daemon = runningDaemon() {
        kill(daemon, mode == "next" ? SIGUSR1 : SIGUSR2)
        mark("signalled daemon")
        exit(0)
    }
    // no daemon (not loaded yet, or crashed) — start one and retry briefly
    let task = Process()
    task.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    task.arguments = ["daemon"]
    try? task.run()
    for _ in 0..<60 {
        usleep(25_000)
        if let daemon = runningDaemon() {
            kill(daemon, mode == "next" ? SIGUSR1 : SIGUSR2)
            exit(0)
        }
    }
    FileHandle.standardError.write("alphatab: daemon would not start\n".data(using: .utf8)!)
    exit(1)
}

// ── daemon ──────────────────────────────────────────────────────────────────
if let existing = runningDaemon() {
    FileHandle.standardError.write("alphatab: daemon already running (pid \(existing))\n".data(using: .utf8)!)
    exit(0)
}
try? String(getpid()).write(toFile: pidFile, atomically: true, encoding: .utf8)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no dock icon, no focus theft

let rowHeight: CGFloat = 26
let padding: CGFloat = 10
let width: CGFloat = 250

let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
// activate() is async — the target app's windows arrive a beat after we draw,
// so sit above the menu bar and re-assert front while visible.
panel.level = .screenSaver
panel.ignoresMouseEvents = true
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

let blur = NSVisualEffectView(frame: panel.contentView!.bounds)
blur.material = .hudWindow
blur.blendingMode = .behindWindow
blur.state = .active
blur.wantsLayer = true
blur.layer?.cornerRadius = 12
blur.layer?.masksToBounds = true
blur.autoresizingMask = [.width, .height]
panel.contentView = blur

var apps: [NSRunningApplication] = []
var rowViews: [NSView] = []
var nameLabels: [NSTextField] = []
var badgeLabels: [NSTextField?] = []
var selection = 0
var visible = false
var lastPress = Date()

func rebuildRows() {
    blur.subviews.forEach { $0.removeFromSuperview() }
    rowViews.removeAll(); nameLabels.removeAll(); badgeLabels.removeAll()

    let shortcuts = shortcutsByBundleID()
    let height = CGFloat(apps.count) * rowHeight + padding * 2
    panel.setContentSize(NSSize(width: width, height: height))

    for (i, a) in apps.enumerated() {
        let y = height - padding - CGFloat(i + 1) * rowHeight
        let row = NSView(frame: NSRect(x: padding / 2, y: y, width: width - padding, height: rowHeight))
        row.wantsLayer = true
        row.layer?.cornerRadius = 6

        let icon = NSImageView(frame: NSRect(x: 6, y: (rowHeight - 18) / 2, width: 18, height: 18))
        icon.image = a.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        row.addSubview(icon)

        let shortcut = a.bundleIdentifier.flatMap { shortcuts[$0] } ?? ""
        let shortcutWidth: CGFloat = shortcut.isEmpty ? 0 : 54

        let label = NSTextField(labelWithString: displayName(a))
        label.frame = NSRect(x: 32, y: (rowHeight - 16) / 2,
                             width: width - padding - 38 - shortcutWidth, height: 16)
        label.lineBreakMode = .byTruncatingTail
        row.addSubview(label)
        nameLabels.append(label)

        if shortcut.isEmpty {
            badgeLabels.append(nil)
        } else {
            let badge = NSTextField(labelWithString: shortcut)
            badge.frame = NSRect(x: width - padding - shortcutWidth, y: (rowHeight - 14) / 2,
                                 width: shortcutWidth - 8, height: 14)
            badge.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            badge.alignment = .right
            row.addSubview(badge)
            badgeLabels.append(badge)
        }

        blur.addSubview(row)
        rowViews.append(row)
    }

    if let screen = NSScreen.main {
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - width / 2,
                                     y: screen.frame.midY - height / 2))
    }
}

func highlight() {
    for i in rowViews.indices {
        let on = i == selection
        rowViews[i].layer?.backgroundColor = on
            ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            : NSColor.clear.cgColor
        nameLabels[i].font = .systemFont(ofSize: 12, weight: on ? .semibold : .regular)
        nameLabels[i].textColor = on ? .white : .labelColor
        badgeLabels[i]?.textColor = on ? .white : .tertiaryLabelColor
    }
}

func focusSelection() {
    guard !hudOnly, apps.indices.contains(selection) else { return }
    apps[selection].unhide()
    apps[selection].activate()
}

func step(_ delta: Int) {
    lastPress = Date()
    if !visible {
        // fresh cycle — the running set may have changed since last time
        apps = dockApps()
        guard apps.count > 1 else { return }
        rebuildRows()
        selection = ((apps.firstIndex { $0.isActive } ?? 0) + delta + apps.count) % apps.count
        highlight()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        visible = true
    } else {
        selection = (selection + delta + apps.count) % apps.count
        highlight()
    }
    focusSelection()
    mark("step -> \(displayName(apps[selection]))")
}

func hide() {
    visible = false
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.18
        panel.animator().alphaValue = 0
    } completionHandler: {
        panel.orderOut(nil)
        panel.alphaValue = 1
    }
}

// ── lifetime ────────────────────────────────────────────────────────────────
// stay up while hyper is held, like ⌘tab's switcher. skhd only reports the
// keypress, never the release, so poll the global modifier state instead.
// a tap that's already released still gets `minVisible` so it stays readable.
let minVisible = ProcessInfo.processInfo.environment["ALPHATAB_DWELL"].flatMap(Double.init) ?? 0.5
let maxVisible = 12.0
let hyper: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

for sig in [SIGUSR1, SIGUSR2, SIGTERM, SIGINT] { signal(sig, SIG_IGN) }
let onNext = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
onNext.setEventHandler { step(1) }
onNext.resume()
let onPrev = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
onPrev.setEventHandler { step(-1) }
onPrev.resume()

func shutdown() {
    if runningDaemon() == nil { try? FileManager.default.removeItem(atPath: pidFile) }
    exit(0)
}
var exitSources: [DispatchSourceSignal] = []  // sources die with their handle
for sig in [SIGTERM, SIGINT] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { shutdown() }
    source.resume()
    exitSources.append(source)
}

Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
    guard visible else { return }
    panel.orderFrontRegardless()  // outlast whatever the activated app brings up
    let held = NSEvent.modifierFlags.intersection(hyper) == hyper
    let since = Date().timeIntervalSince(lastPress)
    guard since >= minVisible else { return }
    if !held || since >= maxVisible { hide() }
}

// clear the pidfile on a clean exit so a stale one never blocks a restart
atexit { try? FileManager.default.removeItem(atPath: pidFile) }

app.run()
