import QtQuick
import QtTest
import "../Selection.js" as Selection

TestCase {
  name: "TrackSelection"
  property var rows: [
    { kind: "item", uri: "spotify:track:a", playlistPosition: 0 },
    { kind: "item", uri: "spotify:track:b", playlistPosition: 1 },
    { kind: "item", uri: "spotify:track:a", playlistPosition: 2 }
  ]
  function test_duplicateOccurrencesStayDistinctAcrossSort() {
    var selected = Selection.select(rows, rows, {}, 2, -1, false, false)
    compare(Selection.items(rows, selected).length, 1)
    compare(Selection.items(rows, selected)[0].playlistPosition, 2)
    var sorted = [rows[2], rows[0], rows[1]]
    selected = Selection.select(rows, sorted, selected, 2, 0, true, false)
    compare(Selection.items(rows, selected).length, 2)
    selected = Selection.select(rows, sorted, selected, 0, 0, true, false)
    compare(Selection.items(rows, selected)[0].uri, "spotify:track:b")
  }
  function test_shiftSelectsVisibleRangeAndPrunesRemovedRows() {
    var filtered = [rows[0], rows[2]]
    var selected = Selection.select(rows, filtered, {}, 1, 0, false, true)
    compare(Selection.items(rows, selected).length, 2)
    selected = Selection.retain([rows[2]], selected)
    compare(Selection.items([rows[2]], selected).length, 1)
    compare(Selection.items([rows[2]], selected)[0].playlistPosition, 2)
  }
}
