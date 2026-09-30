import AppKit
import WebKit
import XCTest
@testable import Lazybones

/// Netflix's navigation script against a page shaped like Netflix's (a header, a billboard, three
/// sliders, a details panel), since the real one needs an account. Each tile is `r<row>c<column>`.
@MainActor
final class NetflixNavTests: XCTestCase {
    private static let page = """
    <html><body style="margin:0;background:#141414;height:1600px">
    <div class="pinning-header" style="position:fixed;top:0;left:0;right:0;height:60px;z-index:9">
      <a data-id="home" href="/browse" style="display:inline-block;width:80px;height:40px">Home</a>
      <button data-id="search" style="width:80px;height:40px">Search</button>
    </div>
    <div class="billboard-row" style="height:400px;padding-top:60px">
      <a data-id="play" data-uia="play-button" href="/watch/1" style="display:inline-block;width:120px;height:44px">Play</a>
      <button data-id="info" style="width:120px;height:44px">More Info</button>
    </div>
    <script>
    const widths = [240, 400, 240];   // the middle row's tiles are wider, so columns don't line up
    widths.forEach((w, r) => {
      const row = document.createElement('div');
      row.className = 'lolomoRow';
      row.style.cssText = 'position:relative;height:200px';
      const slider = document.createElement('div');
      slider.className = 'slider';
      slider.style.cssText = 'overflow:hidden;width:1280px;height:170px';
      const strip = document.createElement('div');
      strip.style.cssText = 'display:flex;width:max-content';
      for (let c = 0; c < 8; c++) {
        const item = document.createElement('div');
        item.className = 'slider-item';
        item.style.cssText = 'width:' + w + 'px;flex:none';
        item.innerHTML = '<div class="title-card"><a class="slider-refocus" data-id="r' + (r + 1) + 'c' + c
          + '" href="/title/' + (r + 1) + '0' + c + '" style="display:block;width:' + (w - 16) + 'px;height:150px"></a></div>';
        strip.appendChild(item);
      }
      slider.appendChild(strip);
      row.appendChild(slider);
      const next = document.createElement('button');
      next.className = 'handle handleNext';
      next.style.cssText = 'position:absolute;right:0;top:0;width:40px;height:150px';
      next.onclick = () => { window.pages = (window.pages || 0) + 1; strip.style.transform = 'translateX(-960px)'; };
      row.appendChild(next);
      document.body.appendChild(row);
    });
    document.addEventListener('click', e => {
      const tile = e.target.closest('.slider-refocus');
      if (tile) {
        e.preventDefault();
        const m = document.createElement('div');
        m.setAttribute('role', 'dialog');
        m.style.cssText = 'position:fixed;left:200px;top:100px;width:800px;height:500px;background:#222;z-index:20';
        m.innerHTML = '<button data-id="close" data-uia="previewModal-closebtn" style="width:40px;height:40px">x</button>'
          + '<a data-id="episode" href="/title/77" style="display:block;width:300px;height:60px">Episode</a>'
          + '<a data-id="modalPlay" data-uia="play-button" href="/watch/9" style="display:block;width:200px;height:50px">Play</a>';
        m.querySelector('[data-uia="previewModal-closebtn"]').onclick = () => m.remove();
        document.body.appendChild(m);
      }
    });
    </script>
    </body></html>
    """


    /// A player page: controls that fade out until the mouse moves, a Skip Intro above them, and a
    /// play/pause button that is replaced by a new element when pressed.
    private static let player = """
    <html><body style="margin:0;background:#000;height:720px">
    <div class="watch-video--player-view" style="position:fixed;inset:0">
      <a data-id="skip" data-uia="player-skip-intro" href="#" style="position:absolute;right:40px;bottom:200px;width:140px;height:44px;display:block">Skip</a>
      <div id="controls" style="position:absolute;left:0;right:0;bottom:40px;height:80px;opacity:0;transition:none">
        <button data-id="back10" style="position:absolute;left:400px;width:60px;height:60px">-10</button>
        <button data-id="play" data-uia="control-play-pause-pause" style="position:absolute;left:480px;width:60px;height:60px">||</button>
        <button data-id="fwd10" style="position:absolute;left:560px;width:60px;height:60px">+10</button>
        <button data-id="audio" style="position:absolute;left:900px;width:60px;height:60px">Aa</button>
      </div>
    </div>
    <script>
    const controls = document.getElementById('controls');
    let hide;
    document.addEventListener('mousemove', () => {
      controls.style.opacity = 1;
      clearTimeout(hide);
      hide = setTimeout(() => { controls.style.opacity = 0; }, 4000);
    });
    window.presses = 0;
    controls.addEventListener('click', e => {
      const b = e.target.closest('button');
      window.presses++;
      if (b.dataset.id === 'play') {
        const fresh = b.cloneNode(true);
        fresh.dataset.uia = 'control-play-pause-play';
        b.replaceWith(fresh);
      }
    });
    </script>
    </body></html>
    """

    private final class Loaded: NSObject, WKNavigationDelegate {
        var done = false
        func webView(_ w: WKWebView, didFinish _: WKNavigation!) { done = true }
    }

    private var window: NSWindow!
    private var webView: WKWebView!

    private func spin(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func run(_ js: String) -> Any? {
        var result: Any?, finished = false
        webView.evaluateJavaScript(js) { r, _ in result = r; finished = true }
        for _ in 0..<100 where !finished { spin(0.02) }
        return result
    }

    /// Loads the fixture at `path` on netflix.com with the script injected, the way `WebPool` does.
    private func load(path: String = "/browse", html: String? = nil) {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            PageScript(source: Netflix.navigation, time: .start).userScript)
        // Off screen, so the test doesn't flash a window.
        window = NSWindow(contentRect: NSRect(x: -12000, y: -12000, width: 1280, height: 720),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        let loaded = Loaded()
        webView.navigationDelegate = loaded
        window.contentView = webView
        window.orderFrontRegardless()
        webView.loadHTMLString(html ?? Self.page, baseURL: URL(string: "https://www.netflix.com" + path)!)
        for _ in 0..<100 where !loaded.done { spin(0.1) }
        XCTAssertTrue(loaded.done)
        spin(0.1)
    }

    override func tearDown() {
        window?.orderOut(nil)
        window = nil
        webView = nil
    }

    /// Presses `key`; whether the page's own handlers were kept from seeing it.
    @discardableResult
    private func press(_ key: String) -> Bool {
        let handled = run("""
        (() => { const e = new KeyboardEvent('keydown', { key: '\(key)', bubbles: true, cancelable: true });
                 document.body.dispatchEvent(e); return e.defaultPrevented; })()
        """) as? Bool == true
        spin(0.05)
        return handled
    }

    /// Several presses in a row.
    private func keys(_ names: String...) { for name in names { press(name) } }

    private var focused: String? {
        run("(() => { const f = document.querySelector('.lazybones-focus'); "
            + "const t = f && (f.dataset.id ? f : f.querySelector('[data-id]')); return t && t.dataset.id; })()") as? String
    }

    /// Focus is on `id` within a few seconds. The script notices the details panel opening and closing
    /// by polling, and timers in a hidden test window run late, so a fixed wait is a race.
    private func focusReaches(_ id: String, within seconds: Double = 3) -> Bool {
        var waited = 0.0
        while focused != id && waited < seconds { spin(0.05); waited += 0.05 }
        return focused == id
    }

    func testTheFirstArrowLandsOnPlay() {
        load()
        press("ArrowDown")
        XCTAssertEqual(focused, "play")
    }

    func testDownEntersTheFirstRowAndRightWalksAlongIt() {
        load()
        keys("ArrowDown", "ArrowDown")
        XCTAssertEqual(focused, "r1c0")
        keys("ArrowRight", "ArrowRight")
        XCTAssertEqual(focused, "r1c2")
        press("ArrowLeft")
        XCTAssertEqual(focused, "r1c1")
    }

    func testTheEdgeOfARowDoesNotWrap() {
        load()
        keys("ArrowDown", "ArrowDown", "ArrowLeft")
        XCTAssertEqual(focused, "r1c0")
    }

    func testUpReachesTheHeaderAndBillboard() {
        load()
        keys("ArrowDown", "ArrowDown", "ArrowUp")
        XCTAssertEqual(focused, "play")
        press("ArrowUp")
        XCTAssertEqual(focused, "home")
    }

    func testUpStillReachesTheHeaderWhileThePageIsScrollingBackToTheTop() {
        load()
        keys("ArrowDown", "ArrowDown", "ArrowUp")
        XCTAssertEqual(focused, "play")
        // No waiting: the scroll to the top is under way and the billboard is still above the header.
        run("scrollTo(0, 300)")
        press("ArrowUp")
        XCTAssertEqual(focused, "home")
    }

    func testDownThenUpComesBackToTheSameColumn() {
        load()
        // r1c3 is at x=832; the row below has tiles centred at 192, 592, 992. Down lands on 992, which is
        // nearer r1c4 (1072) than r1c3, so Up only returns to r1c3 if the column was remembered.
        keys("ArrowDown", "ArrowDown", "ArrowRight", "ArrowRight", "ArrowRight")
        XCTAssertEqual(focused, "r1c3")
        press("ArrowDown")
        XCTAssertEqual(focused, "r2c2")
        press("ArrowUp")
        XCTAssertEqual(focused, "r1c3")
    }

    func testATileAtTheEdgePagesTheSliderBeforeTakingFocus() {
        load()
        keys("ArrowDown", "ArrowDown", "ArrowRight", "ArrowRight", "ArrowRight", "ArrowRight")
        XCTAssertEqual(focused, "r1c4")
        XCTAssertNil(run("window.pages"))
        press("ArrowRight")   // r1c5 is only peeking in
        XCTAssertEqual(focused, "r1c4", "focus waits for the slide")
        spin(1.0)
        XCTAssertEqual(run("window.pages") as? Int, 1)
        XCTAssertEqual(focused, "r1c5")
    }

    func testSelectOpensTheDetailsPanelOnItsPlayButtonAndBackClosesIt() {
        load()
        keys("ArrowDown", "ArrowDown", "ArrowRight")
        press("Enter")
        XCTAssertTrue(focusReaches("modalPlay"), "was \(focused ?? "nil")")
        press("ArrowUp")
        XCTAssertEqual(focused, "episode")
        keys("ArrowDown", "ArrowDown", "ArrowDown")
        XCTAssertEqual(focused, "modalPlay", "arrows stay inside the panel")

        XCTAssertEqual(run("window.__lazybonesBack()") as? Bool, true)
        XCTAssertEqual(run("document.querySelector('[role=dialog]') === null") as? Bool, true)
        XCTAssertTrue(focusReaches("r1c1"), "focus returns to the tile, was \(focused ?? "nil")")
    }

    func testBackFromDeepInThePageGoesToTheTopThenLetsGo() {
        load()
        keys("ArrowDown", "ArrowDown", "ArrowDown", "ArrowDown")
        spin(1.0)
        XCTAssertGreaterThan(run("scrollY") as? Double ?? 0, 50)
        XCTAssertEqual(run("window.__lazybonesBack()") as? Bool, true)
        spin(1.0)
        XCTAssertEqual(run("scrollY") as? Double, 0)
        XCTAssertEqual(run("window.__lazybonesBack()") as? Bool, false, "nothing left to undo: Lazybones takes it")
    }

    private func loadPlayer() { load(path: "/watch/81234567", html: Self.player) }

    func testOnThePlayerUpAndDownWakeTheControlsInsteadOfChangingVolume() {
        loadPlayer()
        XCTAssertTrue(press("ArrowUp"), "Netflix's volume handler must never see it")
        XCTAssertTrue(focusReaches("play"), "was \(focused ?? "nil")")
        XCTAssertEqual(run("document.getElementById('controls').style.opacity") as? String, "1")
    }

    func testOnThePlayerLeftAndRightStillSeekUntilAControlHasFocus() {
        loadPlayer()
        XCTAssertFalse(press("ArrowLeft"))
        XCTAssertFalse(press("ArrowRight"))
        XCTAssertNil(focused)
    }

    func testArrowsMoveBetweenControlsAndSelectPressesOne() {
        loadPlayer()
        press("ArrowUp")
        XCTAssertTrue(focusReaches("play"))
        XCTAssertTrue(press("ArrowRight"), "with a control focused, arrows are ours")
        XCTAssertEqual(focused, "fwd10")
        press("ArrowRight")
        XCTAssertEqual(focused, "audio")
        keys("ArrowLeft", "ArrowLeft")
        XCTAssertEqual(focused, "play")
        press("ArrowUp")
        XCTAssertEqual(focused, "skip", "the Skip Intro button above the controls is reachable")
        press("ArrowDown")
        XCTAssertEqual(focused, "play")
        press("Enter")
        XCTAssertEqual(run("window.presses") as? Int, 1)
    }

    func testFocusFollowsAControlThatIsReplacedWhenPressed() {
        loadPlayer()
        press("ArrowUp")
        XCTAssertTrue(focusReaches("play"))
        press("Enter")
        spin(0.5)
        XCTAssertEqual(run("document.querySelector('[data-id=play]').dataset.uia") as? String, "control-play-pause-play")
        XCTAssertEqual(focused, "play", "the new button has the ring")
        press("ArrowRight")
        XCTAssertEqual(focused, "fwd10")
    }

    func testDownFromTheControlsGivesTheVideoBack() {
        loadPlayer()
        press("ArrowUp")
        XCTAssertTrue(focusReaches("play"))
        press("ArrowDown")
        XCTAssertNil(focused)
        XCTAssertFalse(press("ArrowLeft"), "seeking again")
    }

    func testBackOnThePlayerDropsFocusThenLeavesTheVideo() {
        loadPlayer()
        press("ArrowUp")
        XCTAssertTrue(focusReaches("play"))
        XCTAssertEqual(run("window.__lazybonesBack()") as? Bool, true)
        XCTAssertNil(focused)
        XCTAssertEqual(run("window.__lazybonesBack()") as? Bool, false, "nothing focused: Lazybones goes back a page")
    }

    func testNetflixReplacesTheSharedNavigation() {
        XCTAssertNotNil(Netflix().spatialNavScript)
        XCTAssertNil(YouTube().spatialNavScript)
        XCTAssertNil(Spotify().spatialNavScript)
    }
}
