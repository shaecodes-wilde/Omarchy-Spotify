import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  id: testCase
  property var panelWindow: null
  property int stage: 0
  property int readinessAttempts: 0
  property var playlist: ({kind:"context", type:"playlist", id:"deep", uri:"spotify:playlist:deep", name:"Deep playlist"})
  property var album: ({kind:"context", type:"album", id:"album", uri:"spotify:album:album", name:"Album"})
  function check(value, message) {
    if (!value) {
      run.stop()
      console.error("DESKTOP_NAVIGATION_FAIL: " + message)
      Qt.quit()
      throw new Error(message)
    }
  }
  function ready(value, message) {
    if (value) { readinessAttempts = 0; return true }
    readinessAttempts++
    check(readinessAttempts <= 40, message)
    return false
  }
  function tracks(count) {
    var result = []
    for (var i=0; i<count; i++) result.push({kind:"item", type:"track", id:String(i),
      uri:"spotify:track:" + i, name:"Track " + i, subtitle:"Artist", album:"Album", durationMs:180000})
    return result
  }
  function windowObject() {
    for (var i=0; i<panel.data.length; i++)
      if (panel.data[i].objectName === "spotify-panel-window") return panel.data[i]
    return null
  }
  function findItem(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = findItem(children[i], name)
      if (found) return found
    }
    return null
  }
  function loader(name) { return findItem(panelWindow.contentItem, name) }
  Plugin.Service {
    id: spotifyService
    manifest: ({__sourceDir:"/nonexistent"})
    property int receivedRestoreCount: 0
    property var visibleQueueItems: []
    function setDiscoverySurfaceVisible(key, visible) { }
    function selectHomeTab(tab) { }
    function setUiVisible(key, visible) { }
    function openView(view, force) { activeView = view }
    function loadLibrary(type, append, force) { }
    function loadQueue() { }
    function setQueueVisibleItems(surface, items) { visibleQueueItems = items }
    function checkSavedItems(items) { }
    function openDetail(item, query, count) {
      receivedRestoreCount = Number(count) || 0
      detailItem = item
      detailRestoreTargetCount = receivedRestoreCount
      detailItems = testCase.tracks(receivedRestoreCount || 3)
      detailNext = ""
      detailLoading = false
    }
    function ensureDetailItemCount(count) { receivedRestoreCount = Number(count) || 0 }
    function openPlaylist(item, count) {
      selectedPlaylist = item
      playlistItems = testCase.tracks(Number(count) || 3)
      playlistRestoreTargetCount = Number(count) || 0
    }
  }
  Plugin.Panel { id: panel; service: spotifyService }

  Timer {
    id: run
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      if (stage === 0) {
        spotifyService.auth.customClientId = "invalid"
        spotifyService.auth.sessionChecked = true
        spotifyService.auth.loggedIn = true
        spotifyService.settings = Object.assign({}, spotifyService.settings, {showArtwork:"Off"})
        spotifyService.recentTracks = tracks(3)
        spotifyService.savedTracks = tracks(3)
        panelWindow = windowObject()
        check(!!panelWindow, "Panel window is not discoverable")
        check(!loader("spotify-page-loader").active, "Hidden panel instantiated a page")
        check(!loader("spotify-right-pane-loader").active, "Hidden panel instantiated a drawer")
        panelWindow.implicitWidth = 1280
        panelWindow.implicitHeight = 800
        panel.opened = true
        panel.currentTab = "home"
        panel.homeType = "overview"
      } else if (stage === 1) {
        if (!ready(panel.pageCollections().length === 2, "Cached Home shelves are missing")) return
        panel.openItem(playlist)
        spotifyService.detailItems = tracks(750)
        spotifyService.detailRestoreTargetCount = 750
        panel.detailFilter = "Track"
        panel.detailSort = "name"
        panel.panelCursorRegion = "page"
        panel.panelCursorAction = "list"
        panel.panelCursorActive = true
      } else if (stage === 2) {
        if (!ready(panel.pageCollection() && panel.pageCollection().listCount > 630, "Deep playlist did not finish loading")) return
        panel.pageCollection().restoreCurrentIndex(630)
        panel.rememberScroll("detail:spotify:playlist:deep", 12000)
        panel.openItem(album)
        check(panel.navigationStack[panel.navigationStack.length - 1].focusIndex === 630,
          "Snapshot lost focused row before navigation")
      } else if (stage === 3) {
        panel.goBack()
        check(spotifyService.receivedRestoreCount === 750, "Back lost the loaded playlist target")
        check(panel.detailFilter === "Track" && panel.detailSort === "name", "Back lost filter/sort")
      } else if (stage === 4) {
        if (!ready(!!panel.pageCollection(), "Back did not finish loading its page")) return
        if (panel.pendingFocusIndex >= 0 && panel.focusRestoreAttempts < 20) return
        check(panel.pageCollection().listCurrentIndex === 630, "Back lost focused row: "
          + panel.pageCollection().listCurrentIndex + ", pending " + panel.pendingFocusIndex
          + ", count " + panel.pageCollection().listCount)
        check(panel.scrollFor("detail:spotify:playlist:deep") > 0, "Back lost scroll position")
        panel.goForward()
        check(spotifyService.detailItem.id === "album", "Forward lost selected context")
        panel.sidebarWidth = 300
        panel.sidebarCollapsed = true
        panel.togglePlaylistPin(playlist)
        panel.persistUiState()
        panel.navigationStack = []
        panel.forwardStack = []
        panel.sidebarWidth = 214
        panel.sidebarCollapsed = false
        panel.playlistPins = []
        panel.restoreUiState()
        check(panel.sidebarWidth === 300 && panel.sidebarCollapsed, "Sidebar preferences did not restore")
        check(panel.playlistPins.indexOf("deep") >= 0, "Local pin did not restore")
        check(panel.navigationStack.length > 0, "Session lost navigation history")
        panel.currentTab = "home"
        panel.homeType = "overview"
        panel.toggleRightPane("now-playing")
      } else if (stage === 5) {
        var drawer = loader("spotify-right-pane-loader")
        if (!ready(drawer.active && !!drawer.item, "Now playing drawer did not load")) return
        check(drawer.item.toString().indexOf("NowPlayingPane") >= 0, "Wrong drawer component")
          panel.toggleRightPane("queue")
          spotifyService.queue = tracks(80)
      } else if (stage === 6) {
        if (!ready(loader("spotify-right-pane-loader").item && loader("spotify-right-pane-loader").item.drawer, "Queue did not replace Now playing")) return
        check(spotifyService.visibleQueueItems.length > 0 && spotifyService.visibleQueueItems.length <= 50,
          "Queue metadata was not bounded to visible rows")
        panel.toggleRightPane("queue")
        check(!loader("spotify-right-pane-loader").active, "Closed drawer remains instantiated")
        panel.sidebarCollapsed = false
        panelWindow.implicitWidth = 700
      } else if (stage === 7) {
      } else if (stage === 8) {
        panel.opened = false
        check(!loader("spotify-page-loader").active, "Closed panel retained its page")
        check(spotifyService.visibleQueueItems.length === 0, "Hidden queue retained metadata work")
      } else {
        console.log("DESKTOP_NAVIGATION_PASS")
        Qt.quit()
      }
      stage++
    }
  }
}
