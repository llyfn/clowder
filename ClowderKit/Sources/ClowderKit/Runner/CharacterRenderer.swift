import AppKit
import Darwin

/// Draws runner characters as template images, one NSImage per animation frame.
/// Shapes are simple placeholder art — deliberately code-drawn so there is no
/// asset pipeline; swap for nicer paths anytime without touching callers.
public enum CharacterRenderer {
    public static let frameCount = 6
    public static let size = NSSize(width: 26, height: 17)

    @MainActor
    public static func frames(for character: RunnerCharacter) -> [NSImage] {
        (0..<frameCount).map { frame in
            let image = NSImage(size: size, flipped: false) { _ in
                let phase = Double(frame) / Double(frameCount) * 2 * .pi
                NSColor.black.setFill()
                NSColor.black.setStroke()
                switch character {
                case .cat: drawCat(in: NSZeroRect, phase: phase)
                case .dog: drawDog(in: NSZeroRect, phase: phase)
                case .rocket: drawRocket(in: NSZeroRect, phase: phase)
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    /// Four legs as angled strokes whose angle oscillates with `phase`,
    /// under a capsule body with a head circle and a tail line.
    private static func drawCat(in _: NSRect, phase: Double) {
        let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 7, width: 15, height: 6),
                                xRadius: 3, yRadius: 3)
        body.fill()
        NSBezierPath(ovalIn: NSRect(x: 17, y: 9, width: 6, height: 6)).fill()
        // ears
        let ear = NSBezierPath()
        ear.move(to: NSPoint(x: 19, y: 14)); ear.line(to: NSPoint(x: 20, y: 17)); ear.line(to: NSPoint(x: 21, y: 14))
        ear.fill()
        // tail swings opposite the legs
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 4, y: 11))
        tail.line(to: NSPoint(x: 1, y: 12 + CGFloat(sin(phase)) * 2))
        tail.lineWidth = 1.5
        tail.stroke()
        drawLegs(phase: phase, bodyMinX: 6, bodyMaxX: 17)
    }

    private static func drawDog(in _: NSRect, phase: Double) {
        let body = NSBezierPath(roundedRect: NSRect(x: 3, y: 7, width: 17, height: 7),
                                xRadius: 3.5, yRadius: 3.5)
        body.fill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: 9, width: 7, height: 6)).fill()
        // floppy ear
        NSBezierPath(ovalIn: NSRect(x: 19, y: 12, width: 2.5, height: 4)).fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 3, y: 12))
        tail.line(to: NSPoint(x: 0.5, y: 14 + CGFloat(sin(phase))))
        tail.lineWidth = 1.5
        tail.stroke()
        drawLegs(phase: phase, bodyMinX: 5, bodyMaxX: 18)
    }

    /// Rocket "runs" by bobbing and pulsing its exhaust flame.
    private static func drawRocket(in _: NSRect, phase: Double) {
        let bob = CGFloat(sin(phase)) * 1.5
        let bodyRect = NSRect(x: 8, y: 5 + bob, width: 12, height: 7)
        NSBezierPath(roundedRect: bodyRect, xRadius: 3.5, yRadius: 3.5).fill()
        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: 20, y: 5 + bob))
        nose.line(to: NSPoint(x: 25, y: 8.5 + bob))
        nose.line(to: NSPoint(x: 20, y: 12 + bob))
        nose.fill()
        let flameLength = 3 + CGFloat(abs(sin(phase))) * 4
        let flame = NSBezierPath()
        flame.move(to: NSPoint(x: 8, y: 6.5 + bob))
        flame.line(to: NSPoint(x: 8 - flameLength, y: 8.5 + bob))
        flame.line(to: NSPoint(x: 8, y: 10.5 + bob))
        flame.fill()
    }

    private static func drawLegs(phase: Double, bodyMinX: CGFloat, bodyMaxX: CGFloat) {
        for (i, x) in [bodyMinX, bodyMinX + 3.5, bodyMaxX - 3.5, bodyMaxX].enumerated() {
            // alternating gait: even legs swing with phase, odd legs in counter-phase
            let legPhase = phase + (i.isMultiple(of: 2) ? 0 : .pi)
            let swing = CGFloat(sin(legPhase)) * 2.5
            let leg = NSBezierPath()
            leg.move(to: NSPoint(x: x, y: 8))
            leg.line(to: NSPoint(x: x + swing, y: 2))
            leg.lineWidth = 1.5
            leg.stroke()
        }
    }
}
