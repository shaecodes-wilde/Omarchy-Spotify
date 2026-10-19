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
  property double pendingAt: 0
  property double feedbackAt: 0
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
    visible: root.mode !== "closed"
    Plugin.Panel {
      id: panel
      anchors.fill: parent
      service: service
      opened: root.mode === "full" || root.mode === "navigation"
      currentTab: "library"
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
  Timer {
    interval: 100; running: true
    onTriggered: {
      service.localPlaybackStopped = true
      service.setUiVisible("fixture", root.mode !== "closed")
      if (root.mode !== "closed") service.remotePlayback = { playing: false, progressSeconds: 30,
        receivedAt: Date.now(), device: { id: "fixture-remote", name: "Fixture device", active: true,
        supportsVolume: true, volumePercent: 50 }, item: root.tracks(1,"current")[0] }
      service.activeView = "library"
      if (root.mode !== "closed" && root.mode !== "mini") root.populate()
      console.log("PERFORMANCE_READY")
      if (root.mode !== "closed") feedback.start()
      if (root.mode === "navigation") navigation.start()
    }
  }
  Timer {
    id: feedback
    interval: 100; repeat: true
    property int count: 0
    onTriggered: {
      root.feedbackAt = Date.now()
      if (root.mode === "mini" && miniLoader.item) {
        miniLoader.item.miniCursorActive = true
        miniLoader.item.miniCursor = count % 2 ? "play" : "next"
      } else {
        panel.panelCursorRegion = "footer"
        panel.panelCursorAction = count % 2 ? "play" : "next"
      }
      Qt.callLater(function() {
        console.log("PERFORMANCE_FEEDBACK_MS " + (Date.now()-root.feedbackAt))
        if (feedback.count >= 20) console.log("PERFORMANCE_FEEDBACK_DONE")
      })
      if (++count >= 20) stop()
    }
  }
  IpcHandler {
    target: "benchmark"
    function navigate(): string { root.cycle = 0; navigation.start(); return "ok" }
  }
  Timer {
    id: navigation
    interval: 50; repeat: true
    onTriggered: {
      if (root.cycle >= 20) { stop(); console.log("PERFORMANCE_NAVIGATION_DONE"); return }
      root.pendingAt = Date.now()
      // Alternate a large manually loaded collection with another route. No HTTP/auth.
      service.activeView = "search"
      panel.currentTab = "search"
      service.activeView = "library"
      panel.currentTab = "library"
      root.populate()
      root.cycle++
      Qt.callLater(function() { console.log("PERFORMANCE_NAVIGATION_MS " + (Date.now()-root.pendingAt)) })
    }
  }
}
