import XCTest
@testable import Stylus

// Tests for the Swift-side PlayQueue. Doubles as a behavioural spec
// for parity with the desktop's Stylus::PlayQueue: when shuffle or
// repeat semantics change on the desktop, update both this test
// (to capture the new spec) and PlayQueue.swift (to satisfy it).
//
// Coverage goals:
//   - Cursor mechanics (advance / goBack / jump / setQueue / canAdvance / canGoBack)
//   - Insertions (insertNext / append) on empty + populated queues
//   - Shuffle invariants (current track moves to index 0; same track
//     set survives shuffle; idempotent; insertNext / append while
//     shuffled append to originalTracks)
//   - Unshuffle (restores original order; places playing track at
//     its original index; no-op when not shuffled)
//   - Repeat-mode cycle (off -> all -> one -> off)
//   - advanceForAutoFinish branches per repeat mode
//   - Manual advance never wraps even when repeat=all (matches desktop)
final class PlayQueueTests: XCTestCase
{
    // MARK: - Helpers

    private func track(_ title: String) -> Track
    {
        Track(filePath:        "/test/" + title + ".mp3",
              title:           title,
              artist:          "",
              album:           "",
              genre:           "",
              year:            "",
              trackNumber:     0,
              bpm:             0,
              key:             "",
              durationSeconds: 0,
              isPodcast:       false,
              podcast:         "")
    }

    private func tracks(_ titles: String...) -> [Track]
    {
        titles.map { track($0) }
    }

    // MARK: - setQueue + cursor

    func testSetQueueStartsAtIndex()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 1)
        XCTAssertEqual(q.currentIndex, 1)
        XCTAssertEqual(q.currentTrack?.title, "b")
    }

    func testSetQueueClampsHighIndex()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 99)
        XCTAssertEqual(q.currentIndex, 2)
    }

    func testSetQueueOnEmpty()
    {
        let q = PlayQueue()
        q.setQueue([])
        XCTAssertEqual(q.currentIndex, 0)
        XCTAssertNil(q.currentTrack)
    }

    func testCanAdvanceCanGoBack()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 1)
        XCTAssertTrue(q.canAdvance)
        XCTAssertTrue(q.canGoBack)

        q.setQueue(tracks("a", "b", "c"), startingAt: 0)
        XCTAssertTrue(q.canAdvance)
        XCTAssertFalse(q.canGoBack)

        q.setQueue(tracks("a", "b", "c"), startingAt: 2)
        XCTAssertFalse(q.canAdvance)
        XCTAssertTrue(q.canGoBack)
    }

    // MARK: - advance / goBack / jump

    func testAdvanceWalksToEnd()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 0)
        XCTAssertEqual(q.advance()?.title, "b")
        XCTAssertEqual(q.advance()?.title, "c")
        XCTAssertNil(q.advance(), "manual advance must NOT wrap")
        XCTAssertEqual(q.currentIndex, 2)
    }

    func testGoBackWalksToStart()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 2)
        XCTAssertEqual(q.goBack()?.title, "b")
        XCTAssertEqual(q.goBack()?.title, "a")
        XCTAssertNil(q.goBack())
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testJump()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"))
        XCTAssertEqual(q.jump(to: 2)?.title, "c")
        XCTAssertEqual(q.currentIndex, 2)
        XCTAssertNil(q.jump(to: -1))
        XCTAssertNil(q.jump(to: 99))
        XCTAssertEqual(q.currentIndex, 2, "invalid jumps must not move the cursor")
    }

    // MARK: - insertNext

    func testInsertNextOnEmpty()
    {
        let q = PlayQueue()
        q.insertNext(tracks("x", "y"))
        XCTAssertEqual(q.tracks.map(\.title), ["x", "y"])
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testInsertNextAfterCurrent()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 1)
        q.insertNext(tracks("x", "y"))
        XCTAssertEqual(q.tracks.map(\.title), ["a", "b", "x", "y", "c"])
        XCTAssertEqual(q.currentIndex, 1, "inserting after current must not move the cursor")
    }

    func testInsertNextOfEmptyArrayIsNoOp()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b"))
        q.insertNext([])
        XCTAssertEqual(q.tracks.map(\.title), ["a", "b"])
    }

    // MARK: - append

    func testAppendOnEmpty()
    {
        let q = PlayQueue()
        q.append(tracks("x", "y"))
        XCTAssertEqual(q.tracks.map(\.title), ["x", "y"])
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testAppendAtEnd()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b"))
        q.append(tracks("c", "d"))
        XCTAssertEqual(q.tracks.map(\.title), ["a", "b", "c", "d"])
        XCTAssertEqual(q.currentIndex, 0)
    }

    // MARK: - shuffleAll invariants

    func testShuffleAllNoOpOnEmpty()
    {
        let q = PlayQueue()
        q.shuffleAll()
        XCTAssertFalse(q.isShuffled)
        XCTAssertTrue(q.tracks.isEmpty)
    }

    func testShuffleAllMovesCurrentToIndexZero()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c", "d", "e"), startingAt: 2)  // current = c
        q.shuffleAll()
        XCTAssertTrue(q.isShuffled)
        XCTAssertEqual(q.currentIndex, 0)
        XCTAssertEqual(q.currentTrack?.title, "c")
    }

    func testShuffleAllPreservesTrackSet()
    {
        let q = PlayQueue()
        let titles = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
        q.setQueue(titles.map(track(_:)), startingAt: 4)
        q.shuffleAll()
        XCTAssertEqual(q.tracks.count, titles.count, "no tracks may be lost during shuffle")
        XCTAssertEqual(Set(q.tracks.map(\.title)),
                       Set(titles),
                       "no duplicates may be introduced during shuffle")
    }

    func testShuffleAllIsIdempotentWhileShuffled()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c", "d", "e"), startingAt: 0)
        q.shuffleAll()
        let after = q.tracks.map(\.title)
        q.shuffleAll()  // already shuffled -> no-op
        XCTAssertEqual(q.tracks.map(\.title), after)
    }

    // MARK: - unshuffle

    func testUnshuffleNoOpWhenNotShuffled()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 1)
        q.unshuffle()
        XCTAssertEqual(q.tracks.map(\.title), ["a", "b", "c"])
        XCTAssertEqual(q.currentIndex, 1)
        XCTAssertFalse(q.isShuffled)
    }

    func testUnshuffleRestoresOriginalOrderAndIndex()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c", "d", "e"), startingAt: 2)  // current = c
        q.shuffleAll()
        q.unshuffle()
        XCTAssertFalse(q.isShuffled)
        XCTAssertEqual(q.tracks.map(\.title), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(q.currentIndex, 2,
                       "after unshuffle, current track sits at its original index")
    }

    func testSetShuffledFalseEqualsUnshuffle()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 1)
        q.setShuffled(true)
        XCTAssertTrue(q.isShuffled)
        q.setShuffled(false)
        XCTAssertFalse(q.isShuffled)
        XCTAssertEqual(q.tracks.map(\.title), ["a", "b", "c"])
        XCTAssertEqual(q.currentIndex, 1)
    }

    // MARK: - setQueue resets shuffle

    func testSetQueueResetsShuffleToOff()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 1)
        q.shuffleAll()
        XCTAssertTrue(q.isShuffled)
        q.setQueue(tracks("x", "y", "z"), startingAt: 0)
        XCTAssertFalse(q.isShuffled,
                       "fresh queue load must reset shuffle (matches desktop)")
    }

    // MARK: - insertNext / append while shuffled feed originalTracks

    func testInsertNextWhileShuffledThenUnshuffleIncludesInserted()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 0)
        q.shuffleAll()
        q.insertNext(tracks("x", "y"))
        q.unshuffle()
        XCTAssertEqual(Set(q.tracks.map(\.title)),
                       Set(["a", "b", "c", "x", "y"]),
                       "tracks inserted while shuffled must survive unshuffle")
    }

    func testAppendWhileShuffledThenUnshuffleIncludesAppended()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 0)
        q.shuffleAll()
        q.append(tracks("d", "e"))
        q.unshuffle()
        XCTAssertEqual(Set(q.tracks.map(\.title)),
                       Set(["a", "b", "c", "d", "e"]),
                       "tracks appended while shuffled must survive unshuffle")
    }

    // MARK: - Repeat mode

    func testCycleRepeatMode()
    {
        let q = PlayQueue()
        XCTAssertEqual(q.repeatMode, .off)
        q.cycleRepeatMode()
        XCTAssertEqual(q.repeatMode, .all)
        q.cycleRepeatMode()
        XCTAssertEqual(q.repeatMode, .one)
        q.cycleRepeatMode()
        XCTAssertEqual(q.repeatMode, .off)
    }

    // MARK: - advanceForAutoFinish

    func testAutoFinishOffStopsAtEnd()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b"), startingAt: 1)
        XCTAssertNil(q.advanceForAutoFinish())
    }

    func testAutoFinishOffAdvancesMidQueue()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 0)
        XCTAssertEqual(q.advanceForAutoFinish()?.title, "b")
        XCTAssertEqual(q.currentIndex, 1)
    }

    func testAutoFinishAllWrapsAtEnd()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 2)
        q.repeatMode = .all
        XCTAssertEqual(q.advanceForAutoFinish()?.title, "a",
                       "repeat-all wraps to index 0 at end of queue")
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testAutoFinishAllAdvancesMidQueue()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 0)
        q.repeatMode = .all
        XCTAssertEqual(q.advanceForAutoFinish()?.title, "b")
        XCTAssertEqual(q.currentIndex, 1)
    }

    func testAutoFinishOneReplaysCurrent()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b", "c"), startingAt: 1)
        q.repeatMode = .one
        XCTAssertEqual(q.advanceForAutoFinish()?.title, "b",
                       "repeat-one returns the current track to replay it")
        XCTAssertEqual(q.currentIndex, 1)
    }

    // MARK: - Manual advance never wraps even with repeat-all

    func testManualAdvanceNeverWrapsEvenWithRepeatAll()
    {
        let q = PlayQueue()
        q.setQueue(tracks("a", "b"), startingAt: 1)
        q.repeatMode = .all
        XCTAssertNil(q.advance(),
                     "manual next/prev must never wrap; only auto-advance honours repeat-all")
    }
}
