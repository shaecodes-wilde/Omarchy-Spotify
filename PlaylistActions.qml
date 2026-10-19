import QtQuick
import "Api.js" as Api

// Playlist writes share one lock and stop at the first unconfirmed batch.
Item {
  id: root
  required property var host
  visible: false

  function create(name, callback) {
    var value = String(name || "").trim()
    if (!value || host.playlistActionBusy) return
    var expected = host.dataSerial
    host.playlistActionBusy = true
    host.api.request("POST", "/me/playlists", null, {
      name: value.slice(0, 100), "public": false, description: "Created with Omarchy Spotify"
    }, function(status, payload, error) {
      if (expected !== host.dataSerial) return
      host.playlistActionBusy = false
      if (error) { host.fail(error); return }
      var playlist = Api.normalizePlaylist(payload, 96)
      if (!playlist) { host.fail("Spotify did not return the created playlist. Check your library before retrying."); return }
      host.registerPlaylistCopy(playlist)
      host.succeed("Playlist created")
      if (typeof callback === "function") callback(playlist)
    }, { priority: "interactive", retryRateLimit: false })
  }

  function writeItems(items, playlist, removing) {
    if (!playlist || !playlist.id || !host.playlistEditable(playlist)
        || host.playlistActionBusy) return
    var uris = Api.playlistItemUris(items)
    if (removing) uris = uris.filter(function(uri, index) { return uris.indexOf(uri) === index })
    if (!uris.length) return
    var expected = host.dataSerial
    var completed = 0
    host.playlistActionBusy = true
    function finish(error) {
      if (expected !== host.dataSerial) return
      host.playlistActionBusy = false
      host.reloadPlaylist(playlist)
      if (error) host.fail((completed ? completed + " items confirmed. " : "") + error
        + " Check the playlist before retrying.")
      else host.succeed(removing ? "Removed all copies of selected songs" : "Added to " + String(playlist.name || "playlist"))
    }
    function next() {
      if (expected !== host.dataSerial) return
      if (completed >= uris.length) { finish(""); return }
      var batch = uris.slice(completed, completed + 100)
      var body = removing ? { items: batch.map(function(uri) { return { uri: uri } }) }
        : { uris: batch }
      if (removing && playlist.snapshotId) body.snapshot_id = playlist.snapshotId
      host.api.request(removing ? "DELETE" : "POST",
        "/playlists/" + encodeURIComponent(String(playlist.id)) + "/items", null, body,
        function(status, payload, error) {
          if (expected !== host.dataSerial) return
          if (error) { finish(error); return }
          if (payload && payload.snapshot_id) {
            playlist = Object.assign({}, playlist, { snapshotId: payload.snapshot_id })
            host.updatePlaylistSnapshot(playlist.id, payload.snapshot_id)
          }
          completed += batch.length
          next()
        }, { priority: "interactive", retryRateLimit: false })
    }
    next()
  }

  function update(playlist, name, description) {
    var value = String(name || "").trim()
    if (!value || !host.playlistOwned(playlist) || host.playlistActionBusy) return
    var expected = host.dataSerial
    var fields = { name: value.slice(0, 100), description: String(description || "").slice(0, 300) }
    host.playlistActionBusy = true
    host.api.request("PUT", "/playlists/" + encodeURIComponent(String(playlist.id)), null, fields,
      function(status, payload, error) {
        if (expected !== host.dataSerial) return
        host.playlistActionBusy = false
        if (error) { host.fail(error); return }
        function updated(item) {
          return item && item.type === "playlist" && String(item.id) === String(playlist.id)
            ? Object.assign({}, item, fields) : item
        }
        host.playlists = host.playlists.map(updated)
        host.selectedPlaylist = updated(host.selectedPlaylist)
        host.detailItem = updated(host.detailItem)
        host.succeed("Playlist details updated")
      }, { priority: "interactive", retryRateLimit: false })
  }
}
