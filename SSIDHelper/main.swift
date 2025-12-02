import Cocoa
import CoreWLAN
import CoreLocation

class AppDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    var hasRequestedPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        locationManager.delegate = self

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            hasRequestedPermission = true
        } else {
            printSSIDAndExit()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if hasRequestedPermission {
            // Give a moment for the system to process
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.printSSIDAndExit()
            }
        }
    }

    func printSSIDAndExit() {
        if let client = CWWiFiClient.shared().interface(), let ssid = client.ssid() {
            // Write to stdout
            FileHandle.standardOutput.write((ssid + "\n").data(using: .utf8)!)
        } else {
            FileHandle.standardOutput.write("NO_SSID\n".data(using: .utf8)!)
        }
        NSApplication.shared.terminate(nil)
    }
}

// Check if we should run as GUI app or just try to get SSID directly
let args = CommandLine.arguments
if args.contains("--direct") {
    // Try direct access (for when permission is already granted)
    if let client = CWWiFiClient.shared().interface(), let ssid = client.ssid() {
        print(ssid)
    } else {
        print("NO_SSID")
    }
    exit(0)
} else {
    // Run as GUI app to request/use location permission
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // Don't show in dock
    app.run()
}
