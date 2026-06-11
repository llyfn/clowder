import AppKit
import Darwin

/// Draws runner characters as template images, one NSImage per animation frame.
/// Shapes are simple placeholder art — deliberately code-drawn so there is no
/// asset pipeline; swap for nicer paths anytime without touching callers.
public enum CharacterRenderer {
    public static let frameCount = 6

    public static func size(for character: RunnerCharacter) -> NSSize {
        switch character {
        case .clowder: NSSize(width: 46, height: 17)
        case .cat, .dog, .rocket: NSSize(width: 26, height: 17)
        }
    }

    @MainActor
    public static func frames(for character: RunnerCharacter) -> [NSImage] {
        (0..<frameCount).map { frame in
            let image = NSImage(size: size(for: character), flipped: false) { _ in
                let phase = Double(frame) / Double(frameCount) * 2 * .pi
                NSColor.black.setFill()
                NSColor.black.setStroke()
                switch character {
                case .clowder: drawClowder(phase: phase)
                case .cat: drawCat(phase: phase)
                case .dog: drawDog(phase: phase)
                case .rocket: drawRocket(phase: phase)
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    /// Three cats mid-chase: a kitten trailing, a middle cat, and the leader
    /// out front — each on its own gait phase so the pack ripples.
    private static func drawClowder(phase: Double) {
        drawCat(phase: phase + 4.2, offsetX: 0, scale: 0.62)   // kitten, trailing
        drawCat(phase: phase + 2.1, offsetX: 12, scale: 0.74)
        drawCat(phase: phase, offsetX: 25, scale: 0.84)        // leader
    }

    /// A chibi cat: oversized head, gallop bounce, lagging head bob, curling
    /// tail, paw-like round line caps. `offsetX`/`scale` let the clowder
    /// character place several cats on one canvas.
    private static func drawCat(phase: Double, offsetX: CGFloat = 0, scale: CGFloat = 1) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: offsetX, y: 0)
        context.scaleBy(x: scale, y: scale)

        // Vertical budget on the 17 pt canvas: ear tips peak at
        // headY(max 8.8) + 8 = 16.8 — keep amplitudes small or ears clip.
        let bounce = CGFloat(abs(sin(phase))) * 1.2        // body rises mid-stride
        let headBob = CGFloat(sin(phase + .pi / 3)) * 0.6  // head lags the body

        // Legs first so the body overlaps the hips.
        drawGallopLegs(phase: phase, bounce: bounce)

        // Body: low rounded capsule.
        NSBezierPath(roundedRect: NSRect(x: 5, y: 5 + bounce, width: 13, height: 6),
                     xRadius: 3, yRadius: 3).fill()

        // Head: oversized circle, the main cuteness lever.
        let headY = 7 + bounce + headBob
        NSBezierPath(ovalIn: NSRect(x: 15, y: headY, width: 7, height: 7)).fill()

        // Two pointy ears riding the head's upper edge.
        let ears = NSBezierPath()
        ears.move(to: NSPoint(x: 16.5, y: headY + 5.8))
        ears.line(to: NSPoint(x: 17.3, y: headY + 8))
        ears.line(to: NSPoint(x: 18.6, y: headY + 6.4))
        ears.close()
        ears.move(to: NSPoint(x: 19.4, y: headY + 6.4))
        ears.line(to: NSPoint(x: 20.7, y: headY + 8))
        ears.line(to: NSPoint(x: 21.3, y: headY + 5.6))
        ears.close()
        ears.fill()

        // Tail: curved stroke waving against the stride.
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 6, y: 9 + bounce))
        tail.curve(to: NSPoint(x: 1.5, y: 12.5 + CGFloat(sin(phase)) * 1.8),
                   controlPoint1: NSPoint(x: 3, y: 9.5 + bounce),
                   controlPoint2: NSPoint(x: 1.5, y: 10.5))
        tail.lineWidth = 1.6
        tail.lineCapStyle = .round
        tail.stroke()
    }

    private static func drawDog(phase: Double) {
        let body = NSBezierPath(roundedRect: NSRect(x: 3, y: 7, width: 17, height: 7),
                                xRadius: 3.5, yRadius: 3.5)
        body.fill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: 9, width: 7, height: 6)).fill()
        // floppy ear
        NSBezierPath(ovalIn: NSRect(x: 19, y: 12, width: 2.5, height: 4)).fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 3, y: 12))
        tail.line(to: NSPoint(x: 1.5, y: 14 + CGFloat(sin(phase))))
        tail.lineWidth = 1.5
        tail.stroke()
        drawGallopLegs(phase: phase, bounce: 0)
    }

    /// Rocket "runs" by bobbing and pulsing its exhaust flame.
    private static func drawRocket(phase: Double) {
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

    /// Gallop: back and front leg pairs swing out of phase; each foot lifts
    /// during its forward swing. Round caps read as paws at menu bar size.
    private static func drawGallopLegs(phase: Double, bounce: CGFloat) {
        let legs: [(hipX: CGFloat, legPhase: Double)] = [
            (7, phase),                          // back pair
            (8.5, phase + 0.45),
            (15, phase + .pi * 0.75),            // front pair
            (16.5, phase + .pi * 0.75 + 0.45),
        ]
        for leg in legs {
            let swing = CGFloat(sin(leg.legPhase)) * 3
            let lift = CGFloat(max(0, sin(leg.legPhase + .pi / 2))) * 1.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: leg.hipX, y: 7 + bounce))
            path.line(to: NSPoint(x: leg.hipX + swing, y: 1.5 + lift))
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.stroke()
        }
    }
}
