import CoreGraphics
import Foundation

public enum PanelPlacement {
    public static func toolbarFrame(
        anchor: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 8
    ) -> CGRect {
        let centeredX = anchor.midX - panelSize.width / 2
        let clampedX = clamp(
            centeredX,
            minimum: visibleFrame.minX + gap,
            maximum: visibleFrame.maxX - panelSize.width - gap
        )

        let aboveY = anchor.maxY + gap
        let belowY = anchor.minY - panelSize.height - gap
        let preferredY =
            aboveY + panelSize.height <= visibleFrame.maxY
            ? aboveY
            : belowY
        let clampedY = clamp(
            preferredY,
            minimum: visibleFrame.minY + gap,
            maximum: visibleFrame.maxY - panelSize.height - gap
        )

        return CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: panelSize)
    }

    public static func conversationFrame(
        anchor: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 12
    ) -> CGRect {
        let rightX = anchor.maxX + gap
        let leftX = anchor.minX - panelSize.width - gap
        let preferredX: CGFloat
        if rightX + panelSize.width <= visibleFrame.maxX {
            preferredX = rightX
        } else if leftX >= visibleFrame.minX {
            preferredX = leftX
        } else {
            preferredX = anchor.midX - panelSize.width / 2
        }

        let preferredY = anchor.midY - panelSize.height / 2
        let x = clamp(
            preferredX,
            minimum: visibleFrame.minX + gap,
            maximum: visibleFrame.maxX - panelSize.width - gap
        )
        let y = clamp(
            preferredY,
            minimum: visibleFrame.minY + gap,
            maximum: visibleFrame.maxY - panelSize.height - gap
        )
        return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }

    private static func clamp(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }
        return min(max(value, minimum), maximum)
    }
}
