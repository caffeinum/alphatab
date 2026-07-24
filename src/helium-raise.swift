// run-or-raise for a single Helium (chromium) profile.
//
// `open -b` only activates the app, so it raises whatever window was focused
// last, ignoring profiles. launching the binary with --profile-directory always
// spawns a NEW window instead of raising the existing one. so: find the profile's
// window through the accessibility API and raise it, and only launch when there
// isn't one.
//
// chromium titles multi-profile windows "<tab> - Helium - <profile name>", which
// is the only place the profile is exposed to the outside world.
//
// usage: helium-raise <profile-directory>   e.g. helium-raise "Profile 1"

import Cocoa
import ApplicationServices

let bundleID = "net.imput.helium"
let binary = "/Applications/Helium.app/Contents/MacOS/Helium"
let supportDir = NSHomeDirectory() + "/Library/Application Support/net.imput.helium"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("helium-raise: \(message)\n".data(using: .utf8)!)
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("usage: helium-raise <profile-directory>") }
let profileDir = CommandLine.arguments[1]

// profile display name as chromium writes it into window titles
func profileDisplayName(_ dir: String) -> String {
    let statePath = supportDir + "/Local State"
    guard let data = FileManager.default.contents(atPath: statePath),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let profile = root["profile"] as? [String: Any],
          let cache = profile["info_cache"] as? [String: Any],
          let entry = cache[dir] as? [String: Any],
          let name = entry["name"] as? String
    else { fail("no profile named \(dir) in \(statePath)") }
    return name
}

func launch() -> Never {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: binary)
    task.arguments = ["--profile-directory=\(profileDir)"]
    do { try task.run() } catch { fail("could not launch Helium: \(error)") }
    exit(0)
}

let displayName = profileDisplayName(profileDir)

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    launch()
}

guard AXIsProcessTrusted() else { fail("no accessibility permission — grant it to skhd") }

let axApp = AXUIElementCreateApplication(app.processIdentifier)
var windowsRef: CFTypeRef?
AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
let windows = (windowsRef as? [AXUIElement]) ?? []

func title(_ window: AXUIElement) -> String {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
    return (value as? String) ?? ""
}

// chromium only appends " - Helium - <profile>" once a second profile exists.
// with a single profile open the suffix is absent, so an unsuffixed window is
// the only profile there is and matching it is correct.
let suffix = " - Helium - \(displayName)"
let anySuffixed = windows.contains { title($0).contains(" - Helium - ") }
let match = windows.first { window in
    let t = title(window)
    return t.hasSuffix(suffix) || (!anySuffixed && t.hasSuffix(" - Helium"))
}

guard let window = match else { launch() }

var minimized: CFTypeRef?
AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
if (minimized as? Bool) == true {
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
}

AXUIElementPerformAction(window, kAXRaiseAction as CFString)
AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
app.activate()
