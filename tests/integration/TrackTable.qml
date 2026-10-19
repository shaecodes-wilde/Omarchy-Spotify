import QtQuick
import QtQuick.Window
import Quickshell
import "plugin" as Plugin

ShellRoot {
  id: testCase
  property var changedSettings: ({})
  property var queuedSelection: []
  property var rows: [
    { kind: "item", type: "track", uri: "spotify:track:a", name: "Alpha", album: "Album A", durationMs: 1000, playlistPosition: 0 },
    { kind: "item", type: "track", uri: "spotify:track:b", name: "Beta", album: "Album B", durationMs: 2000, playlistPosition: 1 },
    { kind: "item", type: "track", uri: "spotify:track:a", name: "Alpha", album: "Album A", durationMs: 1000, playlistPosition: 2 }
  ]
  QtObject {
    id: fakeService
    property bool artworkEnabled: false
    property bool uiVisible: true
    property bool accountConnected: true
    property string lastError: ""
    property double searchCooldownUntil: 0
    property var settings: ({ trackDensity: "Compact", trackColumns: "Album + date" })
    function isSaved(item) { return false }
    function persistSettings(value) { changedSettings = value; settings = Object.assign({}, settings, value) }
  }
  Window {
    id: testWindow
    visible: true
    width: 1150
    height: 500
    Plugin.MediaCollection {
      id: collection
      anchors.fill: parent
      service: fakeService
      sourceItems: testCase.rows
      onBatchQueueRequested: function(items) { testCase.queuedSelection = items }
    }
  }
  function init() {
    collection.clearSelection()
    collection.filterText = ""
    collection.sortKey = "default"
    queuedSelection = []
  }
  function test_compactColumnsAndPersistentPreferences() {
    verify(collection.compactRows)
    verify(collection.albumColumn)
    verify(collection.dateColumn)
    collection.cycleColumns()
    compare(changedSettings.trackColumns, "Album")
    verify(!collection.dateColumn)
  }
  function test_selectionAndFilteringNeverPlayOrChangeSourceOrder() {
    collection.selectRow(0, Qt.NoModifier)
    collection.selectRow(2, Qt.ControlModifier)
    compare(collection.selectionCount, 2)
    compare(collection.selectedItems()[1].playlistPosition, 2)
    collection.batchQueueRequested(collection.selectedItems())
    compare(queuedSelection.length, 2)
    collection.filterText = "Beta"
    compare(collection.selectionCount, 0)
    collection.selectAll()
    compare(collection.selectionCount, 1)
    compare(collection.selectedItems()[0].name, "Beta")
    compare(testCase.rows[0].playlistPosition, 0)
  }
  function test_shiftKeyboardSelectionAndFocusRestoration() {
    collection.selectRow(0, Qt.NoModifier)
    collection.keyboardShiftHeld = true
    collection.moveCurrent(1)
    collection.keyboardShiftHeld = false
    compare(collection.selectionCount, 2)
    collection.restoreCurrentIndex(2)
    compare(collection.listCurrentIndex, 2)
  }
  function verify(value) { if (!value) throw new Error("Track table assertion failed") }
  function compare(actual, expected) {
    if (actual !== expected) throw new Error("Track table: " + actual + " !== " + expected)
  }
  Timer {
    interval: 100
    running: true
    onTriggered: {
      init(); test_compactColumnsAndPersistentPreferences()
      init(); test_selectionAndFilteringNeverPlayOrChangeSourceOrder()
      init(); test_shiftKeyboardSelectionAndFocusRestoration()
      console.log("TRACK_TABLE_PASS")
      Qt.quit()
    }
  }

}
