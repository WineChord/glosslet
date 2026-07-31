import AppKit
import ApplicationServices
import GlossletCore

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
        guard Self.isTrusted else {
            return nil
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
        let focusedApplication = unsafeBitCast(
            focusedApplicationValue,
            to: AXUIElement.self
        )

        var processIdentifier: pid_t = 0
        guard
            AXUIElementGetPid(
                focusedApplication,
                &processIdentifier
            ) == .success,
            processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return nil
        }

        guard
            let focusedElementValue = attribute(
                kAXFocusedUIElementAttribute,
                from: focusedApplication
            ),
            CFGetTypeID(focusedElementValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let focusedElement = unsafeBitCast(
            focusedElementValue,
            to: AXUIElement.self
        )
        guard !isSecure(element: focusedElement) else {
            return nil
        }
        guard
            let selectedText = attribute(
                kAXSelectedTextAttribute,
                from: focusedElement
            ) as? String
        else {
            return nil
        }

        let trimmed = selectedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return nil
        }

        let runningApplication = NSRunningApplication(
            processIdentifier: processIdentifier
        )
        let applicationName =
            runningApplication?.localizedName
            ?? L10n.text("Unknown app", "未知应用")
        let selectedRange = selectedTextRange(for: focusedElement)
        let selectionBounds =
            selectedRange
            .flatMap { bounds(for: $0, in: focusedElement) }
            .map(convertAXBoundsToAppKit)
        let selectionEndBounds =
            selectedRange
            .flatMap { trailingBounds(for: $0, in: focusedElement) }
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

        return SelectionSnapshot(
            text: selectedText,
            sourceApplicationName: applicationName,
            sourceBundleIdentifier:
                runningApplication?.bundleIdentifier,
            sourceProcessIdentifier: processIdentifier,
            sourceElementIdentifier: CFHash(focusedElement),
            selectionRange: selectedRange.map {
                NSRange(location: $0.location, length: $0.length)
            },
            bounds: resolvedSelectionBounds,
            anchorBounds: anchorBounds
        )
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
