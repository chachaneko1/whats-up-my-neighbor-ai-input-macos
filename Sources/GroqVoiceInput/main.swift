import AppKit

let app = NSApplication.shared
let delegate = VoiceTypeController()
app.delegate = delegate
app.run()
