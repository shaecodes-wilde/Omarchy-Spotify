import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "plugin" as Plugin

ShellRoot {
  id: fixture
  property int stage: 0
  property bool narrowWindow: Quickshell.env("SPOTIFY_DESKTOP_NARROW") === "1"
  property var panelWindow: null
  property int readinessAttempts: 0
  property var driver: null
  property var queueList: null
  property string screenshotDirectory: Quickshell.env("SPOTIFY_DESKTOP_SCREENSHOTS") || ""
  function check(value, message) {
    if (!value) { run.stop(); console.error("DESKTOP_EVENTS_FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function ready(value, message) {
    if (value) { readinessAttempts = 0; return true }
    readinessAttempts++
    check(readinessAttempts <= 40, message)
    return false
  }
  function find(item, predicate) {
    if (!item) return null
    if (predicate(item)) return item
    var children = item.children || []
    for (var i=0; i<children.length; i++) {
      var result = find(children[i], predicate)
      if (result) return result
    }
    return null
  }
  function listFor(collection) {
    return find(collection, function(item) { return typeof item.itemAtIndex === "function" && "contentY" in item })
  }
  function collectionFor(id) {
    var collections = panel.pageCollections()
    for (var i=0; i<collections.length; i++)
      if (collections[i].keyboardListId === id) return collections[i]
    return null
  }
  function homeRowsReady() {
    var list = listFor(collectionFor("list-home-recent"))
    return list && list.count === 3 && !!list.itemAtIndex(0)
  }
  function row(index) {
    return find(panel.pageCollection(), function(item) {
      return item.itemData && item.itemData.uri === "spotify:track:" + index && typeof item.triggerPrimary === "function"
    })
  }
  function tracks(count) {
    var result = []
    for (var i=0; i<count; i++) result.push({kind:"item", type:"track", id:String(i),
      uri:"spotify:track:" + i, name:["Northern Lights", "Lighthouse", "Wild Coast"][i % 3] + " " + i,
      subtitle:"Harbour Sessions", album:"Coastal Lines", artists:[], durationMs:180000, addedAt:"2026-10-01T12:00:00Z"})
    return result
  }
  function capture(name) {
    if (narrowWindow && name !== "library-narrow") return
    if (!narrowWindow && name === "library-narrow") return
    if (screenshotDirectory) driver.grabImage(panelWindow.contentItem.children[0]).save(screenshotDirectory + "/" + name + ".png")
  }
  function readableTheme() {
    Color.foreground = "#dedede"
    Color.background = "#101315"
    Color.accent = "#7dd3b0"
    Color.muted = "#91999e"
    Color.shellValues = ({})
    Style.styleOverrides = ({"normal-fill-alpha":"0.04", "hover-cursor-fill-alpha":"0.08",
      "selected-fill-alpha":"0.18", "normal-border-alpha":"0.25"})
    Style.fontFamily = "DejaVu Sans"
  }
  Plugin.Service {
    id: spotify
    manifest: ({__sourceDir:"/nonexistent"})
    property int playCalls: 0
    property var playlistAdds: []
    property var resolvedQueueRows: []
    function setDiscoverySurfaceVisible(key, visible) { }
    function selectHomeTab(tab) { }
    function setUiVisible(key, visible) { }
    function openView(view, force) { activeView = view }
    function loadLibrary(type, append, force) { }
    function checkSavedItems(items) { }
    function playItem(item, items, uri, message) { playCalls++ }
    function addItemsToPlaylist(items, playlist) { playlistAdds = items.slice() }
    function loadQueue() { }
    function setQueueVisibleItems(surface, items) { resolvedQueueRows = items }
    function searchAll(query, force) { }
  }
  Plugin.Panel { id: panel; service: spotify }
  Component {
    id: columnProbe
    Plugin.MediaCollection { service:spotify; sourceItems:spotify.savedTracks; width:700; height:400; visible:false }
  }
  Component { id: eventDriver; TestCase { name:"DesktopNativeEvents"; when:false } }
  Component { id: imageUnderlay; Rectangle { color:Color.background; z:-1000; anchors.fill:parent } }
  Timer {
    id: run
    interval: 250
    repeat: true
    running: true
    onTriggered: {
      if (stage === 0) {
        spotify.auth.customClientId = "invalid"
        spotify.auth.sessionChecked = true
        spotify.auth.loggedIn = true
        spotify.settings = Object.assign({}, spotify.settings, {showArtwork:"Off"})
        var saved = tracks(12)
        saved[0].name = "Northern Lights over the Harbour — a long title that should leave the duration visible"
        spotify.savedTracks = saved
        spotify.savedTracksLoaded = true
        spotify.currentUserId = "owner"
        spotify.playlists = [{kind:"context", type:"playlist", id:"target", uri:"spotify:playlist:target", name:"Road trip", ownerId:"owner"}]
        spotify.recentTracks = tracks(3)
        spotify.queue = tracks(100)
        for (var i=0; i<panel.data.length; i++)
          if (panel.data[i].objectName === "spotify-panel-window") panelWindow = panel.data[i]
        check(!!panelWindow, "Missing panel window")
        panelWindow.implicitWidth = narrowWindow ? 700 : 1280
        panelWindow.implicitHeight = 800
        panel.opened = true
        panel.currentTab = "library"
        panel.libraryType = "tracks"
        driver = eventDriver.createObject(panelWindow.contentItem.children[0])
        imageUnderlay.createObject(panelWindow.contentItem.children[0])
        readableTheme()
        var probe = columnProbe.createObject(panel)
        check(probe.albumColumn && !probe.dateColumn, "700px table should show album but not date")
        probe.width = 560
        check(!probe.albumColumn && !probe.dateColumn, "560px table should hide album and date")
        probe.width = 1150
        check(probe.albumColumn && probe.dateColumn, "1150px table should show album and date")
        probe.destroy()
      } else if (stage === 1) {
        if (!ready(!!row(0), "Track delegate not rendered")) return
        var duration = find(row(0), function(item) { return item.objectName === "media-row-duration" })
        check(duration && duration.visible, "Long compact title hid the duration")
        driver.mouseClick(row(0), 120, row(0).height / 3, Qt.LeftButton, Qt.NoModifier)
      } else if (stage === 2) {
        check(panel.pageCollection().selectionCount === 1, "Mouse click did not select a row")
        check(spotify.playCalls === 0, "Mouse click unexpectedly started playback")
        check(panel.panelCursorRegion === "page" && panel.panelCursorAction === "list", "Mouse click did not enter the keyboard list")
        driver.keyClick(Qt.Key_Return)
      } else if (stage === 3) {
        check(spotify.playCalls === 1, "Enter after click did not play exactly once")
        driver.mouseClick(row(0), 120, row(0).height / 3, Qt.LeftButton, Qt.NoModifier)
        driver.keyPress(Qt.Key_Shift)
        driver.keyClick(Qt.Key_Down, Qt.ShiftModifier)
        driver.keyRelease(Qt.Key_Shift)
      } else if (stage === 4) {
        check(panel.pageCollection().selectionCount === 2, "Shift+Down after click did not extend selection")
        check(panel.pageCollection().listCurrentIndex === 1, "Shift+Down did not move to the adjacent row")
        check(spotify.playCalls === 1, "Shift selection started playback")
        capture("library-wide-selection")
        if (!narrowWindow) {
          var target = find(panelWindow.contentItem, function(item) { return item.text === "Road trip" && typeof item.clicked === "function" })
          check(!!target, "Sidebar drop target is missing")
          var source = row(0)
          var destination = target.mapToItem(source, target.width / 2, target.height / 2)
          driver.keyPress(Qt.Key_Control)
          driver.mousePress(source, 120, source.height / 3, Qt.LeftButton, Qt.ControlModifier)
          driver.mouseMove(source, 140, source.height / 3, 20, Qt.LeftButton, Qt.ControlModifier)
          driver.mouseMove(source, destination.x, destination.y, 20, Qt.LeftButton, Qt.ControlModifier)
          driver.mouseRelease(source, destination.x, destination.y, Qt.LeftButton, Qt.ControlModifier)
          driver.keyRelease(Qt.Key_Control)
          check(spotify.playlistAdds.length === 2, "Ctrl-drag did not add the selected rows to the sidebar playlist")
        }
        if (Quickshell.env("SPOTIFY_DESKTOP_KEEP_HINTS") === "0") panel.clearShortcutMode()
        panel.libraryType = "albums"
        panel.currentTab = "home"
        panel.homeType = "overview"
      } else if (stage === 5) {
        if (!ready(homeRowsReady(), "Home recent rows did not finish rendering")) return
        capture("home-wide")
        var savedMore = find(panelWindow.contentItem, function(item) {
          return item.text === "Show all" && item.parent && item.parent.parent
            && item.parent.parent.modelData && item.parent.parent.modelData.type === "saved"
        })
        if (!ready(!!savedMore, "Saved shelf Show all is missing")) return
        if (!narrowWindow) {
          driver.mouseClick(savedMore, savedMore.width / 2, savedMore.height / 2)
          check(panel.currentTab === "library" && panel.libraryType === "tracks", "Saved shelf opened the wrong library category")
        }
        panel.currentTab = "search"
        panel.searchType = "all"
        panel.searchText = "Coast"
        spotify.searchResultQuery = "Coast"
        spotify.searchGroups = Object.assign({}, spotify.searchGroups, {
          track:{items:tracks(4), next:""},
          artist:{items:[{kind:"context", type:"artist", id:"artist", uri:"spotify:artist:artist", name:"Harbour Sessions", subtitle:"Artist"}], next:""},
          album:{items:[{kind:"context", type:"album", id:"album", uri:"spotify:album:album", name:"Coastal Lines", subtitle:"Harbour Sessions"}], next:""}
        })
      } else if (stage === 6) {
        if (!ready(panel.pageCollections().length === 3, "Mixed search did not finish loading")) return
        var artistCollection = collectionFor("list-search-artist")
        var artistList = listFor(artistCollection)
        if (!ready(artistList && artistList.itemAtIndex(0), "Single artist preview did not render")) return
        check(artistList.height >= Style.space(66) && artistList.height >= artistList.itemAtIndex(0).height,
          "Single context preview cropped its row/byline")
        capture("search-all-wide")
        panel.currentTab = "home"
        panel.toggleRightPane("queue")
      } else if (stage === 7) {
        var drawer = find(panelWindow.contentItem, function(item) { return item.objectName === "spotify-right-pane-loader" })
        if (!narrowWindow && !ready(drawer && drawer.status === Loader.Ready, "Queue drawer did not finish loading")) return
        if (!narrowWindow && !ready(homeRowsReady(), "Home shelves were blank beside the queue pane")) return
        capture("queue-pane-wide")
        panel.toggleRightPane("queue")
        panel.currentTab = "queue"
      } else if (stage === 8) {
        queueList = panel.pageListView()
        if (!ready(!!queueList, "Queue list not loaded")) return
        queueList.currentIndex = 50
        queueList.positionViewAtIndex(50, ListView.Beginning)
      } else if (stage === 9) {
        if (!ready(!!queueList.itemAtIndex(50), "Scrolled queue row not instantiated")) return
        queueList.contentY = queueList.itemAtIndex(50).y - queueList.spacing + 1
        check(queueList.indexAt(queueList.width / 2, queueList.contentY + 1) < 0, "Queue test did not start inside spacing")
      } else if (stage === 10) {
        check(spotify.resolvedQueueRows.length > 0 && spotify.resolvedQueueRows[0].uri === "spotify:track:50",
          "Queue spacing resolved rows outside the visible range")
        queueList.positionViewAtEnd()
      } else if (stage === 11) {
        check(spotify.resolvedQueueRows[spotify.resolvedQueueRows.length - 1].uri === "spotify:track:99", "Queue tail omitted the last visible row")
        panel.libraryType = "tracks"
        panel.currentTab = "library"
        if (narrowWindow) check(panelWindow.width === 700, "Narrow layout did not use its initial size")
      } else if (stage === 12) {
        if (!ready(panel.pageCollections().length === 1, "Library did not finish loading")) return
        capture("library-narrow")
        spotify.savedTracks = []
      } else if (stage === 13) {
        capture("library-empty")
        spotify.savedTracksLoading = true
      } else if (stage === 14) {
        check(panel.pageCollection().loading, "Busy library did not expose loading state")
        capture("library-busy")
        spotify.savedTracksLoading = false
        spotify.lastError = "Spotify request failed. Refresh to retry."
      } else if (stage === 15) {
        check(!!find(panelWindow.contentItem, function(item) { return item.text === spotify.lastError }), "Request error is not visible")
        capture("library-error")
        console.log("DESKTOP_EVENTS_PASS: mouse->Enter; mouse->Shift+Down; Ctrl-drag; queue spacing and tail")
        Qt.quit()
      }
      stage++
    }
  }
}
