import Foundation

// The Edit menu of DESIGN.md section 10 is Undo, Redo, Cut, Copy, Paste, Select All, Find and Speech.
// These two defaults are how AppKit is told to leave out the dictation and character-palette items it adds
// to every app; they must be registered before NSApplication builds the menu bar.
UserDefaults.standard.register(defaults: ["NSDisabledDictationMenuItem": true, "NSDisabledCharacterPaletteMenuItem": true])

// `-selfcheck YES` runs the shell's headless checks and exits (0 means green); anything else is the app.
if UserDefaults.standard.bool(forKey: "selfcheck") {
    SelfCheck.runAndExit()
} else {
    BeamApp.main()
}
