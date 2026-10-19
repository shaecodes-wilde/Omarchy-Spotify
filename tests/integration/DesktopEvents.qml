import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "plugin" as Plugin

ShellRoot {
  id: fixture
  property int stage: 0
  property var panelWindow: null
  property var driver: null
  property var queueList: null
  property string screenshotDirectory: Quickshell.env("SPOTIFY_DESKTOP_SCREENSHOTS") || ""
  function check(value, message) {
    if (!value) { run.stop(); console.error("DESKTOP_EVENTS_FAIL: " + message); Qt.quit(); throw new Error(message) }
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
    property var resolvedQueueRows: []
    function setDiscoverySurfaceVisible(key, visible) { }
    function selectHomeTab(tab) { }
    function setUiVisible(key, visible) { }
    function openView(view, force) { activeView = view }
    function loadLibrary(type, append, force) { }
    function checkSavedItems(items) { }
    function playItem(item, items, uri, message) { playCalls++ }
    function loadQueue() { }
    function setQueueVisibleItems(surface, items) { resolvedQueueRows = items }
    function searchAll(query, force) { }
  }
  Plugin.Panel { id: panel; service: spotify }
  Component { id: eventDriver; TestCase { name:"DesktopNativeEvents"; when:false } }
  Component { id: imageUnderlay; Rectangle { color:Color.background; z:-1000; anchors.fill:parent } }
  Timer {
    id: run
    interval: 250
    repeat: true
    running: true
    onTriggered: {
      console.log("DESKTOP_EVENT_STAGE", stage, Date.now())
      if (stage === 0) {
        spotify.auth.customClientId = "invalid"
        spotify.auth.sessionChecked = true
        spotify.auth.loggedIn = true
        spotify.settings = Object.assign({}, spotify.settings, {showArtwork:"Off"})
        spotify.savedTracks = tracks(12)
        spotify.savedTracksLoaded = true
        spotify.recentTracks = tracks(3)
        spotify.queue = tracks(100)
        for (var i=0; i<panel.data.length; i++)
          if (panel.data[i].objectName === "spotify-panel-window") panelWindow = panel.data[i]
        check(!!panelWindow, "Missing panel window")
        panelWindow.implicitWidth = 1280
        panelWindow.implicitHeight = 800
        panel.opened = true
        panel.currentTab = "library"
        panel.libraryType = "tracks"
        driver = eventDriver.createObject(panelWindow.contentItem.children[0])
        imageUnderlay.createObject(panelWindow.contentItem.children[0])
        readableTheme()
      } else if (stage === 1) {
        check(!!row(0), "Track delegate not rendered")
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
        if (Quickshell.env("SPOTIFY_DESKTOP_KEEP_HINTS") !== "1") panel.clearShortcutMode()
        panel.currentTab = "home"
        panel.homeType = "overview"
      } else if (stage === 5) {
        capture("home-wide")
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
        capture("search-all-wide")
        panel.currentTab = "home"
        panel.toggleRightPane("queue")
      } else if (stage === 7) {
        capture("queue-pane-wide")
        panel.toggleRightPane("queue")
        panel.currentTab = "queue"
      } else if (stage === 8) {
        queueList = panel.pageListView()
        check(!!queueList, "Queue list not loaded")
        queueList.currentIndex = 50
        queueList.positionViewAtIndex(50, ListView.Beginning)
      } else if (stage === 9) {
        check(!!queueList.itemAtIndex(50), "Scrolled queue row not instantiated")
        queueList.contentY = queueList.itemAtIndex(50).y - queueList.spacing + 1
        check(queueList.indexAt(queueList.width / 2, queueList.contentY + 1) < 0, "Queue test did not start inside spacing")
      } else if (stage === 10) {
        check(spotify.resolvedQueueRows.length > 0 && spotify.resolvedQueueRows[0].uri === "spotify:track:50",
          "Queue spacing resolved rows outside the visible range")
        queueList.positionViewAtEnd()
      } else if (stage === 11) {
        check(spotify.resolvedQueueRows[spotify.resolvedQueueRows.length - 1].uri === "spotify:track:99", "Queue tail omitted the last visible row")
        panel.currentTab = "library"
        panelWindow.implicitWidth = 700
      } else if (stage === 12) {
        capture("library-narrow")
        spotify.savedTracks = []
      } else if (stage === 13) {
        capture("library-empty")
        console.log("DESKTOP_EVENTS_PASS: mouse->Enter; mouse->Shift+Down; queue spacing and tail")
        Qt.quit()
      }
      stage++
    }
  }
}
