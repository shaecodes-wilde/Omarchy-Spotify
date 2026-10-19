import QtQuick
import QtTest
import ".." as Plugin

TestCase {
  id: testCase
  name: "PlaylistActions"
  property var requests: []
  property var failures: []
  property int reloads: 0
  QtObject {
    id: transport
    function request(method, path, query, body, callback, options) {
      requests.push({ method: method, path: path, body: body, callback: callback, options: options })
    }
  }
  QtObject {
    id: fakeHost
    property var api: transport
    property int dataSerial: 0
    property bool playlistActionBusy: false
    property var playlists: []
    property var selectedPlaylist: null
    property var detailItem: null
    property var playlistItems: []
    property var detailItems: []
    function playlistEditable(playlist) { return !!playlist && playlist.ownerId === "me" }
    function playlistOwned(playlist) { return playlistEditable(playlist) }
    function updatePlaylistSnapshot(id, snapshot) {}
    function registerPlaylistCopy(playlist) { playlists = [playlist].concat(playlists) }
    function reloadPlaylist(playlist) { reloads++ }
    function succeed(message) {}
    function fail(message) { failures.push(message) }
  }
  Component { id: actions; Plugin.PlaylistActions { host: fakeHost } }
  function init() {
    requests = []; failures = []; reloads = 0
    fakeHost.dataSerial = 0; fakeHost.playlistActionBusy = false
    fakeHost.playlists = []; fakeHost.selectedPlaylist = null; fakeHost.detailItem = null
    fakeHost.playlistItems = []; fakeHost.detailItems = []
  }
  function playlist() { return { id: "p", uri: "spotify:playlist:p", type: "playlist", ownerId: "me", snapshotId: "s1" } }
  function test_batchesPreserveOrderAndStopOnUnconfirmedWrite() {
    var item = createTemporaryObject(actions, testCase)
    var rows = []
    for (var i = 0; i < 201; i++) rows.push({ type: "track", uri: "spotify:track:" + i })
    item.writeItems(rows, playlist(), false)
    compare(requests.length, 1)
    compare(requests[0].body.uris.length, 100)
    compare(requests[0].options.retryRateLimit, false)
    requests[0].callback(201, { snapshot_id: "s2" }, "")
    compare(requests.length, 2)
    compare(requests[1].body.uris[0], "spotify:track:100")
    requests[1].callback(0, null, "Outcome unknown")
    compare(requests.length, 2)
    verify(!fakeHost.playlistActionBusy)
    compare(reloads, 1)
    verify(failures[0].indexOf("100 items confirmed") >= 0)
  }
  function test_removeUsesLatestSnapshotAndExplicitUriSemantics() {
    var item = createTemporaryObject(actions, testCase)
    var rows = []
    for (var i = 0; i < 101; i++) rows.push({ type: "track", uri: "spotify:track:" + i })
    rows.push(rows[0])
    item.writeItems(rows, playlist(), true)
    compare(requests[0].body.items.length, 100)
    compare(requests[0].body.snapshot_id, "s1")
    requests[0].callback(200, { snapshot_id: "s2" }, "")
    compare(requests[1].body.snapshot_id, "s2")
    compare(requests[1].body.items.length, 1)
    requests[1].callback(200, {}, "")
    verify(!fakeHost.playlistActionBusy)
  }
  function test_accountChangeIgnoresLateResponseAndPermissionsGuardWrites() {
    var item = createTemporaryObject(actions, testCase)
    item.writeItems([{ type: "track", uri: "spotify:track:a" }], { id: "foreign" }, false)
    compare(requests.length, 0)
    item.update(playlist(), "Updated", "Description")
    fakeHost.dataSerial++
    fakeHost.playlistActionBusy = false
    requests[0].callback(200, {}, "")
    compare(fakeHost.playlists.length, 0)
    compare(reloads, 0)
  }
  function test_metadataUpdatesEveryVisibleCopy() {
    var item = createTemporaryObject(actions, testCase)
    fakeHost.playlists = [playlist()]
    fakeHost.selectedPlaylist = playlist()
    fakeHost.detailItem = playlist()
    item.update(playlist(), "  New title  ", "New description")
    compare(requests[0].body.name, "New title")
    requests[0].callback(200, null, "")
    compare(fakeHost.selectedPlaylist.name, "New title")
    compare(fakeHost.detailItem.description, "New description")
    compare(fakeHost.playlists[0].name, "New title")
  }
  function test_reorderRollsBackAndReconcilesFailure() {
    var item = createTemporaryObject(actions, testCase)
    fakeHost.selectedPlaylist = playlist()
    fakeHost.playlistItems = [
      { kind: "item", uri: "spotify:track:a", playlistPosition: 0 },
      { kind: "item", uri: "spotify:track:b", playlistPosition: 1 }
    ]
    item.reorderPlaylistItem(0, 1, fakeHost.selectedPlaylist, 2, fakeHost.playlistItems)
    compare(fakeHost.playlistItems[0].uri, "spotify:track:b")
    requests[0].callback(0, null, "Not confirmed")
    compare(fakeHost.playlistItems[0].uri, "spotify:track:a")
    compare(reloads, 1)
    verify(!fakeHost.playlistActionBusy)
  }
  function test_reorderIgnoresLateAccountResponse() {
    var item = createTemporaryObject(actions, testCase)
    fakeHost.selectedPlaylist = playlist()
    fakeHost.playlistItems = [
      { kind: "item", uri: "spotify:track:a", playlistPosition: 0 },
      { kind: "item", uri: "spotify:track:b", playlistPosition: 1 }
    ]
    item.reorderPlaylistItem(0, 1, fakeHost.selectedPlaylist, 2, fakeHost.playlistItems)
    fakeHost.dataSerial++
    fakeHost.playlistItems = []
    requests[0].callback(500, null, "old error")
    compare(fakeHost.playlistItems.length, 0)
    compare(failures.length, 0)
  }
}
