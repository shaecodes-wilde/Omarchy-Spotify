import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Plugin
import "plugin/Api.js" as Api

ShellRoot {
  id: root
  property string mode: Quickshell.env("BENCHMARK_MODE")
  property int rowCount: Number(Quickshell.env("BENCHMARK_ROWS"))
  property int cycle: 0
  readonly property bool closedMode: mode === "closed" || mode === "closed-after-use"
  property int httpAttempts: 0
  property bool prepared: false
  property var navigationRows: []
  property var navigationCheckpoint: []
  Plugin.Service { id: service }
  QtObject {
    id: fakeShell
    function serviceFor(id) { return service }
  }
  QtObject {
    id: fakeBar
    property var shell: fakeShell
    property bool vertical: false
    property int barSize: 32
    property string position: "top"
    property var activePopout: null
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    property color foreground: "white"
    property color barForeground: "white"
    property color background: "#111111"
    property color urgent: "#55bb99"
    property string fontFamily: "sans-serif"
    property bool foregroundAnimationEnabled: false
    function hideTooltip(owner) {}
    function showTooltip(owner, text) {}
  }
  Window {
    id: window
    width: 1280; height: 800
    visible: false
    Plugin.Panel {
      id: panel
      anchors.fill: parent
      service: service
      opened: false
      currentTab: "setup"
      libraryType: "tracks"
    }
    Loader {
      id: miniLoader
      source: root.mode === "mini" ? "mini.qml" : ""
      onLoaded: { item.bar = fakeBar; item.popupOpen = true }
    }
  }
  function tracks(count, kind) {
    var rows = []
    for (var i = 0; i < count; i++) {
      var id = (kind + "000000000000000000000" + i).slice(-22)
      var artist = {type: "artist", id: "0000000000000000artist", uri: "spotify:artist:0000000000000000artist", name: "Fixture artist"}
      rows.push(Api.normalizeTrack({ added_at: "2026-10-01T12:00:00Z", track: {
        type: "track", id: id, uri: "spotify:track:" + id, name: "Fixture song " + i,
        artists: [artist], duration_ms: 180000, track_number: i%12+1, disc_number: 1,
        album: { type: "album", id: "00000000000000000album", uri: "spotify:album:00000000000000000album",
          name: "Fixture album", artists: [artist], images: [], release_date: "2026-01-01", total_tracks: 12 }
      } }, 96))
    }
    return rows
  }
  function populate() {
    if (root.mode === "navigation" && prepared) {
      if (service.savedTracks.length !== rowCount) service.savedTracks = navigationRows
      service.savedTracksNext = ""
      service.savedTracksLoaded = true
      return
    }
    service.savedTracks = root.mode === "navigation" ? navigationCheckpoint : tracks(Math.min(180, rowCount), "a")
    service.savedTracksNext = "/me/tracks?offset=180"
    service.savedTracksLoaded = true
    if (typeof service.retainLibraryPage === "function") service.retainLibraryPage("tracks")
    service.savedTracks = root.mode === "navigation" ? navigationRows : tracks(rowCount, "a")
    service.savedTracksNext = ""
  }
  function check(value, message) {
    if (!value) throw new Error("BENCHMARK_INVALID: " + message)
  }
  function populatedPageReady() {
    var collection = panel.pageCollection()
    return panel.pageReady && collection && collection.listCount === root.rowCount
      && collection.sourceItems.length === root.rowCount
  }
  function beginNavigation() {
    check(!navigation.running, "navigation rounds overlapped")
    root.cycle = 0
    navigation.phase = 0
    navigation.searchPresented = 0
    navigation.libraryPresented = 0
    feedback.count = 0
    feedback.expectedAt = Date.now() + feedback.interval
    feedback.start()
    navigation.start()
    return "ok"
  }
  function verifyFrame() {
    check(root.httpAttempts === 0 && !service.accountConnected, "fixture attempted HTTP or acquired an account")
    if (root.closedMode && root.prepared) {
      check(!service.uiVisible && !panel.opened, "closed fixture kept a visible surface")
      if (root.mode === "closed-after-use" && typeof service.trimInactiveLibraryCollections === "function")
        check(service.savedTracks.length <= service.cacheLimit, "closed collection exceeded its retention budget")
      return
    }
    if (root.mode === "mini") {
      check(miniLoader.item && miniLoader.item.opened && miniLoader.item.spotify === service,
        "mini player did not load the fixture service")
      check(service.hasMedia, "mini player has no representative track")
      return
    }
    if (root.mode === "closed") return
    var collection = panel.pageCollection()
    check(panel.opened && panel.currentTab === "library" && panel.pageReady, "populated fixture fell back to another page")
    check(collection && collection.listCount === root.rowCount
      && collection.sourceItems.length === root.rowCount, "populated library rows were not rendered: "
      + (collection ? collection.listCount + "/" + collection.sourceItems.length : "no collection"))
    if (typeof collection.trackTable !== "undefined") check(collection.trackTable, "track table path was bypassed")
  }
  Timer {
    interval: 100; running: true
    onTriggered: {
      service.localPlaybackStopped = true
      // Invalid identity plus rejecting factories make accidental network access fail closed.
      service.auth.customClientId = "invalid"
      var rejectHttp = function() { root.httpAttempts++; throw new Error("BENCHMARK_INVALID: HTTP transport used") }
      service.auth.xhrFactory = rejectHttp
      service.api.xhrFactory = rejectHttp
      service.setUiVisible("fixture", !root.closedMode || root.mode === "closed-after-use")
      if (root.mode !== "closed") service.remotePlayback = { playing: false, progressSeconds: 30,
        receivedAt: Date.now(), device: { id: "fixture-remote", name: "Fixture device", active: true,
        supportsVolume: true, volumePercent: 50 }, item: root.tracks(1,"current")[0] }
      service.activeView = "library"
      if (root.mode === "navigation") {
        navigationRows = root.tracks(root.rowCount, "a")
        navigationCheckpoint = navigationRows.slice(0, Math.min(180, root.rowCount))
      }
      if (root.mode !== "closed" && root.mode !== "mini") {
        root.populate()
        panel.currentTab = "library"
        panel.opened = true
      }
      window.visible = root.mode !== "closed"
      // Allow the real page Loader and ListView to finish before asserting their state.
      verifyReady.deadlineAt = Date.now() + 15000
      verifyReady.start()
    }
  }
  Timer {
    id: verifyReady
    interval: 20; repeat: true
    property double deadlineAt: 0
    onTriggered: {
      root.check(Date.now() <= deadlineAt, "initial page did not become ready within 15 seconds")
      if (root.mode === "mini") {
        if (!miniLoader.item) return
      } else if (root.mode !== "closed") {
        root.check(panel.currentTab === "library", "initial fixture switched to an unexpected page")
        if (!root.populatedPageReady()) return
      }
      stop()
      root.verifyFrame()
      if (root.mode === "closed-after-use") {
        panel.opened = false
        window.visible = false
        service.setUiVisible("fixture", false)
      }
      root.prepared = true
      root.verifyFrame()
      console.log("PERFORMANCE_READY")
      if (root.mode === "navigation") root.beginNavigation()
      else if (!root.closedMode) {
        feedback.expectedAt = Date.now() + feedback.interval
        feedback.start()
      }
    }
  }
  Timer {
    id: feedback
    interval: 100; repeat: true
    property int count: 0
    property double expectedAt: 0
    onTriggered: {
      var startedAt = Date.now()
      console.log("PERFORMANCE_EVENT_LOOP_LAG_MS " + Math.max(0, startedAt - expectedAt))
      expectedAt = startedAt + interval
      if (root.mode === "mini" && miniLoader.item) {
        miniLoader.item.miniCursorActive = true
        miniLoader.item.miniCursor = count % 2 ? "play" : "next"
      } else {
        panel.panelCursorActive = true
        panel.panelCursorRegion = "footer"
        panel.panelCursorAction = count % 2 ? "play" : "next"
      }
      var finished = ++count >= 20 && (root.mode !== "navigation" || !navigation.running)
      Qt.callLater(function() {
        console.log("PERFORMANCE_FEEDBACK_MS " + (Date.now()-startedAt))
        if (finished) console.log("PERFORMANCE_FEEDBACK_DONE")
      })
      if (finished) stop()
    }
  }
  IpcHandler {
    target: "benchmark"
    function navigate(): string { return root.beginNavigation() }
    function verify(): string { root.verifyFrame(); return "ok" }
  }
  Timer {
    id: navigation
    interval: 20; repeat: true
    property int phase: 0
    property int searchPresented: 0
    property int libraryPresented: 0
    property double deadlineAt: 0
    property double startedAt: 0
    onTriggered: {
      root.check(root.httpAttempts === 0, "navigation attempted HTTP")
      if (phase === 0) {
        if (root.cycle >= 20) {
          root.check(searchPresented === 20 && libraryPresented === 20, "navigation skipped a presented route")
          stop()
          console.log("PERFORMANCE_NAVIGATION_DONE")
          return
        }
        startedAt = Date.now()
        deadlineAt = startedAt + 15000
        panel.currentTab = "search"
        service.activeView = "search"
        phase = 1
        return
      }
      root.check(Date.now() <= deadlineAt, "navigation page did not become ready within 15 seconds")
      if (phase === 1) {
        root.check(panel.currentTab === "search", "Search route was cancelled or replaced")
        if (!panel.pageReady) return
        searchPresented++
        console.log("PERFORMANCE_SEARCH_PRESENTED")
        // Keep the loaded Search page through another event/frame before leaving it.
        phase = 2
        return
      }
      if (phase === 2) {
        root.check(panel.currentTab === "search" && panel.pageReady, "Search disappeared before presentation")
        panel.currentTab = "library"
        service.activeView = "library"
        root.populate()
        deadlineAt = Date.now() + 15000
        phase = 3
        return
      }
      root.check(panel.currentTab === "library", "Library route was cancelled or replaced")
      if (!root.populatedPageReady()) return
      root.verifyFrame()
      libraryPresented++
      console.log("PERFORMANCE_LIBRARY_PRESENTED")
      console.log("PERFORMANCE_NAVIGATION_MS " + (Date.now()-startedAt))
      root.cycle++
      phase = 0
    }
  }
}
