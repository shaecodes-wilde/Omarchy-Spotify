import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Plugin

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
      source: root.mode === "mini" ? "mini.qml" : ""
      onLoaded: { item.bar = fakeBar; item.popupOpen = true }
    }
  }
  function tracks(count, kind) {
    var rows = []
    for (var i = 0; i < count; i++) rows.push({ type: "track", id: kind + i,
      uri: "spotify:track:" + kind + i, name: "Fixture song " + i,
      artist: "Fixture artist", artists: [{id: "artist", name: "Fixture artist"}],
      album: "Fixture album", durationMs: 180000, imageUrl: "" })
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
      panel.panelCursorRegion = "footer"
      panel.panelCursorAction = count % 2 ? "play" : "next"
      Qt.callLater(function() { console.log("PERFORMANCE_FEEDBACK_MS " + (Date.now()-root.feedbackAt)) })
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
