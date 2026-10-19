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
    service.savedTracks = tracks(Math.min(180, rowCount), "a")
    service.savedTracksNext = "/me/tracks?offset=180"
    service.savedTracksLoaded = true
    if (typeof service.retainLibraryPage === "function") service.retainLibraryPage("tracks")
    service.savedTracks = tracks(rowCount, "a")
    service.savedTracksNext = ""
  }
  function check(value, message) {
    if (!value) throw new Error("BENCHMARK_INVALID: " + message)
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
    check(panel.opened && panel.currentTab === "library", "populated fixture fell back to another page")
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
      if (root.mode !== "closed" && root.mode !== "mini") {
        root.populate()
        panel.currentTab = "library"
        panel.opened = true
      }
      window.visible = root.mode !== "closed"
      // Allow the real page Loader and ListView to finish before asserting their state.
      verifyReady.start()
    }
  }
  Timer {
    id: verifyReady
    interval: 100
    onTriggered: {
      root.verifyFrame()
      if (root.mode === "closed-after-use") {
        panel.opened = false
        window.visible = false
        service.setUiVisible("fixture", false)
      }
      root.prepared = true
      root.verifyFrame()
      console.log("PERFORMANCE_READY")
      if (!root.closedMode) {
        feedback.expectedAt = Date.now() + feedback.interval
        feedback.start()
      }
      if (root.mode === "navigation") navigation.start()
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
      Qt.callLater(function() {
        console.log("PERFORMANCE_FEEDBACK_MS " + (Date.now()-startedAt))
        if (feedback.count >= 20) console.log("PERFORMANCE_FEEDBACK_DONE")
      })
      if (++count >= 20) stop()
    }
  }
  IpcHandler {
    target: "benchmark"
    function navigate(): string { root.cycle = 0; navigation.start(); return "ok" }
    function verify(): string { root.verifyFrame(); return "ok" }
  }
  Timer {
    id: navigation
    interval: 50; repeat: true
    onTriggered: {
      if (root.cycle >= 20) { stop(); console.log("PERFORMANCE_NAVIGATION_DONE"); return }
      var startedAt = Date.now()
      // Alternate a large manually loaded collection with another route. No HTTP/auth.
      service.activeView = "search"
      panel.currentTab = "search"
      service.activeView = "library"
      panel.currentTab = "library"
      root.populate()
      root.cycle++
      Qt.callLater(function() { console.log("PERFORMANCE_NAVIGATION_MS " + (Date.now()-startedAt)) })
    }
  }
}
