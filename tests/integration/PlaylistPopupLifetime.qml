import QtQuick
import QtTest
import Quickshell
import "plugin" as Plugin

ShellRoot {
  id: fixture
  property int stage: 0
  property double closeDeadlineAt: 0
  property var panelWindow: null
  property var driver: null
  property var picker: null
  property var contextMenu: null
  property var firstPending: null
  property var secondPending: null
  property var firstItems: [
    {kind:"item", type:"track", id:"a", uri:"spotify:track:a", name:"First A", subtitle:"Artist", artists:[], albumItem:null, externalUrl:"", durationMs:180000},
    {kind:"item", type:"track", id:"b", uri:"spotify:track:b", name:"First B", subtitle:"Artist", artists:[], albumItem:null, externalUrl:"", durationMs:180000}
  ]
  property var secondItems: [{kind:"item", type:"track", id:"c", uri:"spotify:track:c", name:"Second", subtitle:"Artist", artists:[], albumItem:null, externalUrl:"", durationMs:180000}]
  function check(value, message) {
    if (!value) { run.stop(); console.error("PLAYLIST_POPUP_LIFETIME_FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function released(value, message) {
    if (value) return true
    check(Date.now() < closeDeadlineAt, message)
    return false
  }
  function object(name) {
    for (var i=0; i<panel.data.length; i++)
      if (panel.data[i].objectName === name) return panel.data[i]
    return null
  }
  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i=0; i<children.length; i++) {
      var result = find(children[i], name)
      if (result) return result
    }
    return null
  }
  Plugin.Service {
    id: spotify
    manifest: ({__sourceDir:"/nonexistent"})
    property var createRequests: []
    property var addedBatches: []
    function setDiscoverySurfaceVisible(key, visible) { }
    function selectHomeTab(tab) { }
    function setUiVisible(key, visible) { }
    function openView(view, force) { activeView = view }
    function loadLibrary(type, append, force) { }
    function checkSavedItems(items) { }
    function createPlaylist(name, callback) { createRequests = createRequests.concat([{name:name, callback:callback}]) }
    function addItemsToPlaylist(items, playlist) { addedBatches = addedBatches.concat([{items:items, playlist:playlist}]) }
  }
  Plugin.Panel { id: panel; service:spotify }
  Component { id: eventDriver; TestCase { name:"PlaylistPopupInput"; when:false } }
  Timer {
    id: run
    interval: 150
    repeat: true
    running: true
    onTriggered: {
      if (stage === 0) {
        spotify.auth.customClientId = "invalid"
        spotify.auth.sessionChecked = true
        spotify.auth.loggedIn = true
        spotify.settings = Object.assign({}, spotify.settings, {showArtwork:"Off"})
        panelWindow = object("spotify-panel-window")
        picker = object("spotify-playlist-picker")
        contextMenu = object("spotify-media-context-menu")
        check(panelWindow && picker && contextMenu, "Popup objects unavailable")
        panel.opened = true
        panel.currentTab = "library"
        driver = eventDriver.createObject(panelWindow.contentItem.children[0])
        panel.openPlaylistPicker(firstItems)
        firstPending = panel.pendingPlaylistItem
        panel.newPlaylistName = "Created A"
      } else if (stage === 1) {
        var createButton = find(picker.contentItem, "playlist-picker-create")
        check(createButton && createButton.enabled, "Create button unavailable")
        driver.mouseClick(createButton, createButton.width / 2, createButton.height / 2)
        check(spotify.createRequests.length === 1, "Create click did not start a request")
        picker.close()
        closeDeadlineAt = Date.now() + 2000
      } else if (stage === 2) {
        if (!released(panel.pendingPlaylistItem === null, "Closed picker retained selected rows")) return
        panel.openPlaylistPicker(secondItems)
        secondPending = panel.pendingPlaylistItem
        panel.newPlaylistName = "Draft B"
      } else if (stage === 3) {
        spotify.createRequests[0].callback({kind:"context", type:"playlist", id:"created", uri:"spotify:playlist:created", name:"Created A"})
        check(spotify.addedBatches.length === 1 && spotify.addedBatches[0].items === firstPending,
          "Delayed create added a different selection")
        check(spotify.addedBatches[0].items[0].uri === "spotify:track:a", "Delayed create lost original rows")
        check(picker.opened && panel.pendingPlaylistItem === secondPending && panel.newPlaylistName === "Draft B",
          "Delayed create closed or reset a newer picker")
        picker.close()
        closeDeadlineAt = Date.now() + 2000
      } else if (stage === 4) {
        if (!released(panel.pendingPlaylistItem === null, "Second picker retained its batch after close")) return
        panel.openMediaContext(firstItems[0], 20, 20, Array(1000).fill(firstItems[0]), "", 0)
        contextMenu.close()
        closeDeadlineAt = Date.now() + 2000
        check(panel.contextItem === firstItems[0] && panel.contextSourceItems.length === 1000,
          "Context cleanup ran before the click handler could use its item")
      } else if (stage === 5) {
        if (!released(panel.contextItem === null && panel.contextSourceItems.length === 0, "Closed context retained its source array")) return
        panel.openMediaContext(firstItems[0], 20, 20, firstItems, "", 0)
        contextMenu.close()
        panel.openMediaContext(secondItems[0], 20, 20, secondItems, "", 0)
      } else if (stage === 6) {
        check(contextMenu.opened && panel.contextItem === secondItems[0], "Deferred cleanup cleared a reopened context menu")
        panel.openPlaylistPicker(firstItems)
        panel.close()
        closeDeadlineAt = Date.now() + 2000
        check(!picker.opened && panel.pendingPlaylistItem === null, "Panel close retained its picker/batch")
      } else {
        if (!released(!contextMenu.opened && panel.contextItem === null && panel.contextSourceItems.length === 0,
          "Panel close retained context references")) return
        console.log("PLAYLIST_POPUP_LIFETIME_PASS")
        Qt.quit()
      }
      stage++
    }
  }
}
