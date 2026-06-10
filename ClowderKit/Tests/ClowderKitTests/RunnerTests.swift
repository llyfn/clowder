import Testing
import AppKit
@testable import ClowderKit

struct RunnerTests {
    @Test func sequencerWrapsAround() {
        var seq = FrameSequencer(frameCount: 3)
        #expect(seq.index == 0)
        seq.advance(); seq.advance(); seq.advance()
        #expect(seq.index == 0)
    }

    @Test func intervalShrinksWithLoadAndClamps() {
        let idle = FrameSequencer.interval(forLoad: 0)
        let half = FrameSequencer.interval(forLoad: 0.5)
        let full = FrameSequencer.interval(forLoad: 1)
        #expect(idle > half && half > full)
        #expect(FrameSequencer.interval(forLoad: -1) == idle)   // clamped
        #expect(FrameSequencer.interval(forLoad: 9) == full)    // clamped
    }

    @MainActor
    @Test func rendererProducesTemplateFramesForEveryCharacter() {
        for character in RunnerCharacter.allCases {
            let frames = CharacterRenderer.frames(for: character)
            #expect(frames.count == CharacterRenderer.frameCount)
            for frame in frames {
                #expect(frame.isTemplate)
                #expect(frame.size.height == CharacterRenderer.size.height)
            }
        }
    }

    @MainActor
    @Test func catFramesAreDistinct() {
        let catFrames = CharacterRenderer.frames(for: .cat)
        let tiff0 = catFrames[0].tiffRepresentation
        let tiff1 = catFrames[1].tiffRepresentation
        #expect(tiff0 != nil && tiff1 != nil && tiff0 != tiff1)
    }
}
