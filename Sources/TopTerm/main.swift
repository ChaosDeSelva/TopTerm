import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
#if DEBUG
if CommandLine.arguments.contains("--self-test") { exit(SmokeChecks.run()) }
#endif
let delegate = AppDelegate()
application.delegate = delegate
application.run()
