import UIKit
import XCTest

/// Configure the actual XCTest simulator through Apple's public Settings UI.
/// https://support.apple.com/en-us/123635 documents this mode and navigation path.
enum IPadFullScreenAppsPreflight {
    private static let category = "Multitasking & Gestures"
    private static let modes = ["Full Screen Apps", "Windowed Apps", "Stage Manager"]

    static func configureIfNeeded(in testCase: XCTestCase) throws {
        #if targetEnvironment(simulator)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        guard #available(iOS 26.0, *) else { return }

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        var stage = "launch-settings"
        defer {
            if settings.state != .notRunning { settings.terminate() }
        }
        do {
            settings.launch()
            guard settings.wait(for: .runningForeground, timeout: 15) else {
                throw Failure(stage: stage)
            }
            stage = "open-multitasking-and-gestures"
            try openModePage(settings)
            stage = "select-full-screen-apps"
            if !fullScreenIsSelected(settings) {
                guard let control = modeElements(modes[0], in: settings)
                    .first(where: { $0.isHittable && $0.isEnabled }) else {
                    throw Failure(stage: stage)
                }
                // Tap the observed, named public control; never infer screen coordinates.
                control.tap()
            }
            stage = "verify-full-screen-apps"
            guard waitUntil(settings, timeout: 12, { fullScreenIsSelected(settings) }) else {
                throw Failure(stage: stage)
            }
            attachDiagnostics(settings, to: testCase, stage: "verified", failed: false)
        } catch {
            attachDiagnostics(settings, to: testCase, stage: stage, failed: true)
            // A thrown setup error prevents the journey from running in an unknown mode.
            throw error
        }
        #endif
    }

    private static func openModePage(_ settings: XCUIApplication) throws {
        let navigationReady = {
            categoryRow(in: settings) != nil
                || (settings.searchFields.firstMatch.exists && settings.searchFields.firstMatch.isHittable)
                || settingsSidebar(in: settings) != nil || modePageExists(settings)
        }
        // A cold Settings AX snapshot can consume the waiter deadline before its
        // next snapshot becomes ready. Recheck once without extending the wait.
        guard waitUntil(settings, timeout: 10, navigationReady) || navigationReady() else {
            throw Failure(stage: "settings-navigation-not-ready")
        }
        if modePageExists(settings) { return }
        // Settings can restore its previous scroll position. Scroll only a container
        // identified by public Settings sidebar labels, never the whole application.
        for _ in 0..<8 {
            if let row = categoryRow(in: settings), row.isHittable {
                row.tap()
                guard waitUntil(settings, timeout: 12, { modePageExists(settings) }) else {
                    throw Failure(stage: "multitasking-page-did-not-open")
                }
                return
            }
            guard let sidebar = settingsSidebar(in: settings) else { break }
            sidebar.swipeUp()
        }

        // Use the public search field if the sidebar row wasn't exposed by AX.
        let search = settings.searchFields.firstMatch
        for _ in 0..<8 {
            if search.exists && search.isHittable { break }
            guard let sidebar = settingsSidebar(in: settings) else { break }
            sidebar.swipeDown()
        }
        guard search.exists && search.isHittable else {
            throw Failure(stage: "settings-category-and-search-unavailable")
        }
        search.tap()
        if let previous = search.value as? String, previous != "Search", !previous.isEmpty {
            guard previous.count <= 128 else { throw Failure(stage: "settings-search-not-empty") }
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        search.typeText("Multitasking")
        guard waitUntil(settings, timeout: 12, {
            categoryRow(in: settings)?.isHittable == true
        }), let result = categoryRow(in: settings) else {
            throw Failure(stage: "settings-search-result-unavailable")
        }
        result.tap()
        guard waitUntil(settings, timeout: 12, { modePageExists(settings) }) else {
            throw Failure(stage: "searched-multitasking-page-did-not-open")
        }
    }

    private static func categoryRow(in settings: XCUIApplication) -> XCUIElement? {
        let rows = settings.cells.containing(.staticText, identifier: category).allElementsBoundByIndex
        if let row = rows.first(where: { $0.exists && $0.isHittable }) { return row }
        return settings.buttons.matching(NSPredicate(format: "label == %@", category))
            .allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable })
    }

    private static func settingsSidebar(in settings: XCUIApplication) -> XCUIElement? {
        let labels = ["Airplane Mode", "Wi-Fi", "Bluetooth", "General", "Accessibility",
                      "Display & Brightness", "Home Screen & App Library", "Battery",
                      "Privacy & Security", "Apps"]
        for type in [XCUIElement.ElementType.table, .collectionView, .scrollView] {
            for container in settings.descendants(matching: type).allElementsBoundByIndex {
                guard container.exists && container.isHittable else { continue }
                let recognized = labels.filter {
                    container.staticTexts.matching(NSPredicate(format: "label == %@", $0)).firstMatch.exists
                }
                if recognized.count >= 2 { return container }
            }
        }
        return nil
    }

    private static func modeElements(_ mode: String, in settings: XCUIApplication) -> [XCUIElement] {
        // AX can expose a card as a button, a radio control, or a labelled child.
        // Only named mode elements are examined; the Preferences hierarchy is never logged.
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
                                    mode, mode + ", ", mode + "\n")
        return settings.descendants(matching: .any).matching(predicate).allElementsBoundByIndex.filter {
            switch $0.elementType {
            case .button, .cell, .radioButton, .checkBox, .switch, .staticText, .image:
                return $0.exists
            case .other:
                return $0.exists && $0.label == mode
            default:
                return false
            }
        }
    }

    private static func modePageExists(_ settings: XCUIApplication) -> Bool {
        !modeElements(modes[0], in: settings).isEmpty && !modeElements(modes[1], in: settings).isEmpty
    }

    private static func selected(_ element: XCUIElement) -> Bool {
        if element.isSelected { return true }
        guard let value = element.value as? String else { return false }
        if ["Selected", "Checked"].contains(value) { return true }
        // Numeric/on values are meaningful only on an explicit checkable AX control.
        switch element.elementType {
        case .radioButton, .checkBox, .switch:
            return ["1", "On"].contains(value)
        default:
            return false
        }
    }

    private static func fullScreenIsSelected(_ settings: XCUIApplication) -> Bool {
        guard modePageExists(settings), modeElements(modes[0], in: settings).contains(where: selected) else {
            return false
        }
        return modes.dropFirst().allSatisfy { !modeElements($0, in: settings).contains(where: selected) }
    }

    private static func waitUntil(_ settings: XCUIApplication, timeout: TimeInterval,
                                  _ condition: @escaping () -> Bool) -> Bool {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: settings)
        return XCTWaiter.wait(for: [ready], timeout: timeout) == .completed
    }

    private static func attachDiagnostics(_ settings: XCUIApplication, to testCase: XCTestCase,
                                          stage: String, failed: Bool) {
        var lines = ["iPad simulator Full Screen Apps preflight", "stage=\(stage)",
                     "settingsState=\(settings.state.rawValue)"]
        guard settings.state == .runningForeground else {
            let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
            attachment.name = "ipad-full-screen-apps-preflight"
            attachment.lifetime = .keepAlways
            testCase.add(attachment)
            return
        }
        lines.append("categoryRowHittable=\(categoryRow(in: settings) != nil)")
        lines.append("searchFieldExists=\(settings.searchFields.firstMatch.exists)")
        lines.append("searchFieldHittable=\(settings.searchFields.firstMatch.isHittable)")
        lines.append("recognizedSidebarExists=\(settingsSidebar(in: settings) != nil)")
        lines.append("fullScreenSelectionVerified=\(fullScreenIsSelected(settings))")
        let safeValues = ["0", "1", "On", "Off", "Selected", "Not Selected", "Checked", "Unchecked"]
        for mode in modes {
            let elements = modeElements(mode, in: settings)
            lines.append("mode=\(mode) observedElements=\(elements.count)")
            for element in elements.prefix(6) {
                let value = element.value as? String
                let safeValue = value.map { safeValues.contains($0) ? $0 : "<unrecognized>" } ?? "<none>"
                let frame = element.frame
                lines.append("type=\(element.elementType.rawValue) selected=\(element.isSelected) "
                             + "hittable=\(element.isHittable) enabled=\(element.isEnabled) value=\(safeValue) "
                             + "x=\(frame.minX) y=\(frame.minY) width=\(frame.width) height=\(frame.height)")
            }
            // Successful journeys export exactly their ten review PNGs. Capture a
            // failed mode control only; a Settings root screenshot can expose account PII.
            if failed, let element = elements.first(where: { $0.isHittable && $0.elementType != .other }) {
                let screenshot = XCTAttachment(screenshot: element.screenshot())
                screenshot.name = "ipad-preflight-failed-" + mode.replacingOccurrences(of: " ", with: "-")
                screenshot.lifetime = .keepAlways
                testCase.add(screenshot)
            }
        }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "ipad-full-screen-apps-preflight"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    private struct Failure: LocalizedError {
        let stage: String
        var errorDescription: String? {
            "iPad Settings preflight could not verify Full Screen Apps (\(stage)); review journey aborted."
        }
    }
}
