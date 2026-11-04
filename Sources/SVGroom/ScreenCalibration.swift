import AppKit

/// Millimetres on screen: the physical size the display reports, corrected by a ruler
/// calibration kept per display. The correction is a ratio, so it still holds after
/// changing the display's resolution.
enum ScreenCalibration {
    static let didChange = Notification.Name("ScreenCalibration.didChange")
    private static let defaultsKey = "screenCalibration"

    static func pointsPerMM(_ screen: NSScreen) -> CGFloat { reportedPointsPerMM(screen) * factor(screen) }

    /// Physical size of the display in mm, oriented like the screen, when it reports one.
    static func reportedSizeMM(_ screen: NSScreen) -> CGSize? {
        guard let id = displayID(screen) else { return nil }
        let s = CGDisplayScreenSize(id)
        guard s.width > 0, s.height > 0 else { return nil }
        let rotated = (s.width > s.height) != (screen.frame.width > screen.frame.height)
        return rotated ? CGSize(width: s.height, height: s.width) : s
    }

    /// 72 points per inch when the display doesn't say.
    static func reportedPointsPerMM(_ screen: NSScreen) -> CGFloat {
        guard let mm = reportedSizeMM(screen) else { return 72 / 25.4 }
        return screen.frame.width / mm.width
    }

    static func factor(_ screen: NSScreen) -> CGFloat {
        guard let key = key(screen), let f = stored[key] else { return 1 }
        return f
    }

    static func setFactor(_ factor: CGFloat, for screen: NSScreen) {
        guard let key = key(screen) else { return }
        var all = stored
        all[key] = abs(factor - 1) < 0.00001 ? nil : factor
        UserDefaults.standard.set(all, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static var stored: [String: Double] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Stays the same for a display across launches and reconnections.
    private static func key(_ screen: NSScreen) -> String? {
        guard let id = displayID(screen) else { return nil }
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}
