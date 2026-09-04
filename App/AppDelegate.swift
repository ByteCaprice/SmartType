import AppKit
import InputMethodKit

@MainActor @objc(AppDelegate)
class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer!
    private var statusBarController: StatusBarController!
    func applicationDidFinishLaunching(_: Notification) {
        Log.appDelegate.info("applicationDidFinishLaunching called")

        guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String else {
            Log.appDelegate.error("Failed to read InputMethodConnectionName from Info.plist")
            return
        }

        // Verify InputController is discoverable by IMKServer
        if let controllerClass = Bundle.main.infoDictionary?["InputMethodServerControllerClass"] as? String {
            guard NSClassFromString(controllerClass) != nil else {
                Log.appDelegate.error("Input method server controller class was not found")
                return
            }
            Log.appDelegate.info("Resolved input method server controller class")
        }

        Log.appDelegate.info("Starting IMKServer")

        server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)

        Log.appDelegate.info("IMKServer created successfully")

        statusBarController = StatusBarController()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        SettingsWindowController.shared.showWindow()
        return true
    }

    func applicationWillTerminate(_: Notification) {
        Log.appDelegate.info("Application terminating")
    }
}
