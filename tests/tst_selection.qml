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
    var selected = Selection.select(rows, {}, 2, -1, false, false)
    compare(Selection.items(rows, selected).length, 1)
    compare(Selection.items(rows, selected)[0].playlistPosition, 2)
    var sorted = [rows[2], rows[0], rows[1]]
    selected = Selection.select(sorted, selected, 2, 0, true, false)
    compare(Selection.items(rows, selected).length, 2)
    selected = Selection.select(sorted, selected, 0, 0, true, false)
    compare(Selection.items(rows, selected)[0].uri, "spotify:track:b")
  }
  function test_shiftSelectsVisibleRangeAndPrunesRemovedRows() {
    var filtered = [rows[0], rows[2]]
    var selected = Selection.select(filtered, {}, 1, 0, false, true)
    compare(Selection.items(rows, selected).length, 2)
    selected = Selection.retain([rows[2]], selected)
    compare(Selection.items([rows[2]], selected).length, 1)
    compare(Selection.items([rows[2]], selected)[0].playlistPosition, 2)
  }
  function test_largeSortedSelectionKeepsEveryDuplicateOccurrence() {
    var source = []
    for (var i = 0; i < 10000; i++) source.push({ kind: "item", uri: "spotify:track:" + (i % 2), playlistPosition: i })
    var visible = source.filter(function(item) { return item.playlistPosition % 2 === 0 }).reverse()
    var started = Date.now()
    var selected = Selection.select(visible, {}, visible.length - 1, 0, false, true)
    var result = Selection.items(source, selected)
    compare(result.length, 5000)
    compare(result[0].playlistPosition, 0)
    compare(result[4999].playlistPosition, 9998)
    console.log("SELECTION_10K_MS " + (Date.now() - started))
  }
}
