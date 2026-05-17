import AppKit
import CodexNotifierCore
import Foundation

struct MacOSNotificationFocusUserInfo {
    private static let focusTargetKey = "codexNotifierFocusTarget"

    static func make(focusTarget: MacOSFocusTarget?) -> [AnyHashable: Any] {
        guard let focusTarget,
              let data = try? JSONEncoder().encode(focusTarget) else {
            return [:]
        }

        return [focusTargetKey: String(decoding: data, as: UTF8.self)]
    }

    static func focusTarget(from userInfo: [AnyHashable: Any]) -> MacOSFocusTarget? {
        guard let value = userInfo[focusTargetKey] as? String else {
            return nil
        }

        return try? JSONDecoder().decode(MacOSFocusTarget.self, from: Data(value.utf8))
    }
}

struct MacOSFocusController {
    private let activateTarget: (MacOSFocusTarget) -> Bool

    init(activateTarget: @escaping (MacOSFocusTarget) -> Bool = MacOSFocusController.activateRunningApplication) {
        self.activateTarget = activateTarget
    }

    @discardableResult
    func focus(_ target: MacOSFocusTarget) -> Bool {
        activateTarget(target)
    }

    private static func activateRunningApplication(_ target: MacOSFocusTarget) -> Bool {
        let runningApplications = NSWorkspace.shared.runningApplications
        let processMatch = target.processIdentifier.flatMap { processIdentifier in
            runningApplications.first {
                $0.processIdentifier == processIdentifier
                    && $0.bundleIdentifier == target.bundleIdentifier
            }
        }
        let bundleMatch = runningApplications.first {
            $0.bundleIdentifier == target.bundleIdentifier
        }

        guard let application = processMatch ?? bundleMatch else {
            return false
        }

        return application.activate(options: [.activateAllWindows])
    }
}
