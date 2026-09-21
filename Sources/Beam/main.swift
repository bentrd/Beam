import Foundation

// `-selfcheck YES` runs the shell's headless checks and exits (0 means green); anything else is the app.
if UserDefaults.standard.bool(forKey: "selfcheck") {
    SelfCheck.runAndExit()
} else {
    BeamApp.main()
}
