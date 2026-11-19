import Foundation
import Testing
@testable import OraloCore

struct FollowSessionTests {
    private let ids = (0..<5).map { _ in UUID() }

    @Test func rejectsEmptyAndAmbiguousScripts() {
        #expect(throws: FollowSession.ConfigurationError.emptyScript) {
            try FollowSession(cueIDs: [])
        }
        #expect(throws: FollowSession.ConfigurationError.duplicateCueIDs) {
            try FollowSession(cueIDs: [ids[0], ids[0]])
        }
    }

    @Test func uncertainSpeechHoldsAndNearbyEvidenceRecovers() throws {
        var session = try FollowSession(cueIDs: ids)
        session.resume()
        let token = session.contextToken
        let held = session.apply(.uncertain, contextToken: token, sequence: 0)
        #expect(held)
        #expect(session.mode == .holding)
        #expect(session.currentCueID == ids[0])
        let recovered = session.apply(.matchedCue(ids[1]), contextToken: token, sequence: 1)
        #expect(recovered)
        #expect(session.mode == .following)
        #expect(session.currentCueID == ids[1])
    }

    @Test(arguments: [0, 3])
    func manualSelectionWinsOverPendingResults(target: Int) throws {
        var session = try FollowSession(cueIDs: ids)
        session.resume()
        let staleToken = session.contextToken
        let selected = session.selectCue(ids[target])
        let staleMatch = session.apply(.matchedCue(ids[1]), contextToken: staleToken, sequence: 99)
        let staleHold = session.apply(.uncertain, contextToken: staleToken, sequence: 100)
        #expect(selected)
        #expect(!staleMatch)
        #expect(!staleHold)
        #expect(session.currentCueID == ids[target])
        #expect(session.mode == .following)
    }

    @Test func pauseAndResumeDoNotReplayOldAudio() throws {
        var session = try FollowSession(cueIDs: ids)
        session.resume()
        let staleToken = session.contextToken
        session.pause()
        let selected = session.selectCue(ids[2])
        #expect(selected)
        #expect(session.mode == .paused)
        let whilePaused = session.apply(.matchedCue(ids[3]), contextToken: session.contextToken, sequence: 0)
        #expect(!whilePaused)
        session.resume()
        let staleMatch = session.apply(.matchedCue(ids[3]), contextToken: staleToken, sequence: 99)
        let freshMatch = session.apply(.matchedCue(ids[3]), contextToken: session.contextToken, sequence: 0)
        #expect(!staleMatch)
        #expect(freshMatch)
        #expect(session.currentCueID == ids[3])
    }

    @Test func rejectsDistantBackwardUnknownAndReorderedResults() throws {
        var session = try FollowSession(cueIDs: ids)
        session.resume()
        let token = session.contextToken
        let distant = session.apply(.matchedCue(ids[4]), contextToken: token, sequence: 0)
        let unknown = session.apply(.matchedCue(UUID()), contextToken: token, sequence: 1)
        let next = session.apply(.matchedCue(ids[1]), contextToken: token, sequence: 4)
        let reordered = session.apply(.matchedCue(ids[2]), contextToken: token, sequence: 3)
        let duplicate = session.apply(.matchedCue(ids[2]), contextToken: token, sequence: 4)
        let backward = session.apply(.matchedCue(ids[0]), contextToken: token, sequence: 5)
        #expect(!distant && !unknown && !reordered && !duplicate && !backward)
        #expect(next)
        #expect(session.currentCueID == ids[1])
    }

    @Test func manualNavigationDoesNotStartRecognition() throws {
        var session = try FollowSession(cueIDs: ids)
        let selected = session.selectCue(ids[2])
        #expect(selected)
        #expect(session.mode == .ready)
        let beforeStart = session.apply(.matchedCue(ids[3]), contextToken: session.contextToken, sequence: 0)
        #expect(!beforeStart)
        let token = session.contextToken
        let unknown = session.selectCue(UUID())
        #expect(!unknown)
        #expect(session.contextToken == token)
        #expect(session.currentCueID == ids[2])
    }

    @Test func endedSessionRejectsEveryLaterMovement() throws {
        var session = try FollowSession(cueIDs: ids)
        session.resume()
        let token = session.contextToken
        session.end()
        session.resume()
        session.pause()
        let selected = session.selectCue(ids[4])
        let lateMatch = session.apply(.matchedCue(ids[1]), contextToken: token, sequence: 1)
        #expect(!selected)
        #expect(!lateMatch)
        #expect(session.mode == .ended)
        #expect(session.currentCueID == ids[0])
    }
}
