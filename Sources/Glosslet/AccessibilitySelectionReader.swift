import AppKit
import ApplicationServices
import GlossletCore

enum AccessibilitySelectionReadFailure: String {
    case processNotTrusted
    case focusedApplicationUnavailable
    case glossletIsFocused
    case focusedElementUnavailable
    case secureTextField
    case selectedTextUnavailable
    case emptySelection
}

enum AccessibilitySelectionReadResult {
    case selection(SelectionSnapshot)
    case unavailable(AccessibilitySelectionReadFailure)
}

struct AccessibilitySelectionReader {
    private static let bundleIdentifier = "com.winechord.glosslet"

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestTrustPrompt() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        requestTrustPrompt()
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:"
                    + "com.apple.preference.security"
                    + "?Privacy_Accessibility"
            )
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func repairTrust() throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = [
            "reset",
            "Accessibility",
            bundleIdentifier,
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AccessibilityPermissionRepairError.failed(
                detail.flatMap { $0.isEmpty ? nil : $0 }
            )
        }

        openAccessibilitySettings()
    }

    func currentSelection(anchorHint: CGPoint? = nil) -> SelectionSnapshot? {
        switch readSelection(anchorHint: anchorHint) {
        case .selection(let selection):
            selection
        case .unavailable:
            nil
        }
    }

    func readSelection(
        anchorHint: CGPoint? = nil
    ) -> AccessibilitySelectionReadResult {
        guard Self.isTrusted else {
            return .unavailable(.processNotTrusted)
        }

        let focusedResult = focusedSelection(anchorHint: anchorHint)
        if case .selection = focusedResult {
            return focusedResult
        }
        if case .unavailable(.secureTextField) = focusedResult {
            return focusedResult
        }

        guard let anchorHint else {
            return focusedResult
        }
        let pointerResult = pointerSelection(
            at: anchorHint,
            anchorHint: anchorHint
        )
        if case .selection = pointerResult {
            return pointerResult
        }
        if case .unavailable(.secureTextField) = pointerResult {
            return pointerResult
        }
        return focusedResult
    }

    func readSelection(
        in processIdentifier: pid_t,
        anchorHint: CGPoint? = nil
    ) -> AccessibilitySelectionReadResult {
        guard Self.isTrusted else {
            return .unavailable(.processNotTrusted)
        }
        guard processIdentifier > 0 else {
            return .unavailable(.focusedApplicationUnavailable)
        }
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return .unavailable(.glossletIsFocused)
        }
        let application = AXUIElementCreateApplication(processIdentifier)
        guard
            let focusedElementValue = attribute(
                kAXFocusedUIElementAttribute,
                from: application
            ),
            CFGetTypeID(focusedElementValue) == AXUIElementGetTypeID()
        else {
            return .unavailable(.focusedElementUnavailable)
        }
        let focusedElement = unsafeBitCast(
            focusedElementValue,
            to: AXUIElement.self
        )
        return selection(
            from: focusedElement,
            processIdentifier: processIdentifier,
            anchorHint: anchorHint
        )
    }

    private func focusedSelection(
        anchorHint: CGPoint?
    ) -> AccessibilitySelectionReadResult {
        guard let focusedApplication = focusedApplication() else {
            return .unavailable(.focusedApplicationUnavailable)
        }
        guard
            let processIdentifier = processIdentifier(
                for: focusedApplication
            )
        else {
            return .unavailable(.focusedApplicationUnavailable)
        }
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return .unavailable(.glossletIsFocused)
        }
        return readSelection(
            in: processIdentifier,
            anchorHint: anchorHint
        )
    }

    private func pointerSelection(
        at appKitPoint: CGPoint,
        anchorHint: CGPoint?
    ) -> AccessibilitySelectionReadResult {
        guard let element = element(at: appKitPoint) else {
            return .unavailable(.focusedElementUnavailable)
        }
        guard let processIdentifier = processIdentifier(for: element) else {
            return .unavailable(.focusedElementUnavailable)
        }
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return .unavailable(.glossletIsFocused)
        }
        return selection(
            from: element,
            processIdentifier: processIdentifier,
            anchorHint: anchorHint ?? appKitPoint
        )
    }

    private func selection(
        from element: AXUIElement,
        processIdentifier: pid_t,
        anchorHint: CGPoint?
    ) -> AccessibilitySelectionReadResult {
        guard !isSecure(element: element) else {
            return .unavailable(.secureTextField)
        }
        guard
            let selectedText = attribute(
                kAXSelectedTextAttribute,
                from: element
            ) as? String
        else {
            return .unavailable(.selectedTextUnavailable)
        }
        let trimmed = selectedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return .unavailable(.emptySelection)
        }

        let runningApplication = NSRunningApplication(
            processIdentifier: processIdentifier
        )
        let applicationName =
            runningApplication?.localizedName
            ?? L10n.text("Unknown app", "未知应用")
        let selectedRange = selectedTextRange(for: element)
        let selectionBounds =
            selectedRange
            .flatMap { bounds(for: $0, in: element) }
            .map(convertAXBoundsToAppKit)
        let selectionEndBounds =
            selectedRange
            .flatMap { trailingBounds(for: $0, in: element) }
            .map(convertAXBoundsToAppKit)
        let pointerBounds =
            anchorHint
            .flatMap(pointerAnchorBounds)
        let anchorBounds =
            pointerBounds
            ?? selectionEndBounds
            ?? selectionBounds
            ?? .zero
        let resolvedSelectionBounds = selectionBounds ?? .zero

        return .selection(
            SelectionSnapshot(
                text: selectedText,
                sourceApplicationName: applicationName,
                sourceBundleIdentifier:
                    runningApplication?.bundleIdentifier,
                sourceProcessIdentifier: processIdentifier,
                sourceElementIdentifier: CFHash(element),
                selectionRange: selectedRange.map {
                    NSRange(location: $0.location, length: $0.length)
                },
                bounds: resolvedSelectionBounds,
                anchorBounds: anchorBounds
            )
        )
    }

    private func processIdentifier(for element: AXUIElement) -> pid_t? {
        var processIdentifier: pid_t = 0
        guard
            AXUIElementGetPid(element, &processIdentifier) == .success,
            processIdentifier > 0
        else {
            return nil
        }
        return processIdentifier
    }

    private func attribute(
        _ name: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                name as CFString,
                &value
            ) == .success
        else {
            return nil
        }
        return value
    }

    private func focusedApplication() -> AXUIElement? {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            frontmostApplication.processIdentifier > 0
        {
            return AXUIElementCreateApplication(
                frontmostApplication.processIdentifier
            )
        }

        let system = AXUIElementCreateSystemWide()
        guard
            let focusedApplicationValue = attribute(
                kAXFocusedApplicationAttribute,
                from: system
            ),
            CFGetTypeID(focusedApplicationValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(
            focusedApplicationValue,
            to: AXUIElement.self
        )
    }

    private func element(at appKitPoint: CGPoint) -> AXUIElement? {
        guard let axPoint = convertAppKitPointToAX(appKitPoint) else {
            return nil
        }
        let system = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard
            AXUIElementCopyElementAtPosition(
                system,
                Float(axPoint.x),
                Float(axPoint.y),
                &element
            ) == .success
        else {
            return nil
        }
        return element
    }

    private func isSecure(element: AXUIElement) -> Bool {
        let subrole =
            attribute(
                kAXSubroleAttribute,
                from: element
            ) as? String
        return subrole == "AXSecureTextField"
    }

    private func selectedTextRange(for element: AXUIElement) -> CFRange? {
        guard
            let rangeValueReference = attribute(
                kAXSelectedTextRangeAttribute,
                from: element
            ),
            CFGetTypeID(rangeValueReference) == AXValueGetTypeID()
        else {
            return nil
        }
        let rangeValue = unsafeBitCast(
            rangeValueReference,
            to: AXValue.self
        )
        guard
            AXValueGetType(rangeValue) == .cfRange
        else {
            return nil
        }

        var range = CFRange()
        guard
            AXValueGetValue(
                rangeValue,
                .cfRange,
                &range
            )
        else {
            return nil
        }
        guard range.location != kCFNotFound, range.length > 0 else {
            return nil
        }
        return range
    }

    private func bounds(
        for range: CFRange,
        in element: AXUIElement
    ) -> CGRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }
        var boundsValue: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsValue
            ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let boundsAXValue = unsafeBitCast(boundsValue, to: AXValue.self)
        guard
            AXValueGetType(boundsAXValue) == .cgRect
        else {
            return nil
        }

        var bounds = CGRect.zero
        guard
            AXValueGetValue(
                boundsAXValue,
                .cgRect,
                &bounds
            ), isUsableAXBounds(bounds)
        else {
            return nil
        }
        return bounds
    }

    private func trailingBounds(
        for selectedRange: CFRange,
        in element: AXUIElement
    ) -> CGRect? {
        let insertionRange = CFRange(
            location: selectedRange.location + selectedRange.length,
            length: 0
        )
        if let insertionBounds = bounds(for: insertionRange, in: element) {
            return insertionBounds
        }

        let finalCharacterRange = CFRange(
            location: selectedRange.location + selectedRange.length - 1,
            length: 1
        )
        return bounds(for: finalCharacterRange, in: element)
    }

    private func isUsableAXBounds(_ bounds: CGRect) -> Bool {
        !bounds.isNull
            && !bounds.isInfinite
            && bounds.origin.x.isFinite
            && bounds.origin.y.isFinite
            && bounds.width.isFinite
            && bounds.height.isFinite
            && bounds.height > 0
    }

    private func pointerAnchorBounds(for point: CGPoint) -> CGRect? {
        guard
            point.x.isFinite,
            point.y.isFinite,
            NSScreen.screens.contains(where: {
                $0.frame.insetBy(dx: -2, dy: -2).contains(point)
            })
        else {
            return nil
        }
        return CGRect(x: point.x, y: point.y, width: 1, height: 1)
    }

    private func convertAppKitPointToAX(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite else {
            return nil
        }
        for screen in NSScreen.screens where screen.frame.contains(point) {
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else {
                continue
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let quartzFrame = CGDisplayBounds(displayID)
            return CGPoint(
                x: quartzFrame.minX + point.x - screen.frame.minX,
                y: quartzFrame.minY + screen.frame.maxY - point.y
            )
        }
        return nil
    }

    private func convertAXBoundsToAppKit(_ bounds: CGRect) -> CGRect {
        for screen in NSScreen.screens {
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else {
                continue
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let quartzFrame = CGDisplayBounds(displayID)
            guard
                quartzFrame.intersects(bounds)
                    || quartzFrame.contains(
                        CGPoint(x: bounds.midX, y: bounds.midY)
                    )
            else {
                continue
            }

            return CGRect(
                x: screen.frame.minX + bounds.minX - quartzFrame.minX,
                y: screen.frame.maxY - (bounds.maxY - quartzFrame.minY),
                width: max(bounds.width, 1),
                height: max(bounds.height, 1)
            )
        }

        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: bounds.minX,
            y: primaryHeight - bounds.maxY,
            width: max(bounds.width, 1),
            height: max(bounds.height, 1)
        )
    }
}

private enum AccessibilityPermissionRepairError: LocalizedError {
    case failed(String?)

    var errorDescription: String? {
        switch self {
        case .failed(let detail):
            return detail
                ?? L10n.text(
                    "macOS could not reset the old Accessibility entry.",
                    "macOS 未能重置旧的辅助功能权限条目。"
                )
        }
    }
}
