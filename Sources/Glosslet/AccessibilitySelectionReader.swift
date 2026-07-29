import AppKit
import ApplicationServices
import GlossletCore

struct AccessibilitySelectionReader {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestTrustPrompt() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func currentSelection() -> SelectionSnapshot? {
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
        let bounds =
            selectionBounds(
                for: focusedElement
            ) ?? fallbackBounds()

        return SelectionSnapshot(
            text: selectedText,
            sourceApplicationName: applicationName,
            sourceBundleIdentifier:
                runningApplication?.bundleIdentifier,
            sourceProcessIdentifier: processIdentifier,
            bounds: convertAXBoundsToAppKit(bounds)
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

    private func selectionBounds(for element: AXUIElement) -> CGRect? {
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
            ), !bounds.isNull, !bounds.isInfinite
        else {
            return nil
        }
        return bounds
    }

    private func fallbackBounds() -> CGRect {
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: location.x,
            y: primaryHeight - location.y,
            width: 1,
            height: 1
        )
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
