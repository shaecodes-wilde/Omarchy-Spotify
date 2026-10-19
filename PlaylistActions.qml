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
  function finishPlaylistConversion(error) {
    host.playlistConversionBusy = false
    host.playlistActionBusy = false
    host.statusMessage = ""
    if (error) host.fail(error)
  }

  function collectPlaylistForCopy(playlist, path, collected, expected, callback) {
    var first = !path
    var requestPath = path || "/playlists/" + encodeURIComponent(String(playlist.id)) + "/items"
    host.api.request("GET", requestPath, first ? { limit: 50 } : null, null,
      function(status, payload, error) {
        if (expected !== host.dataSerial) return
        if (error) { callback([], error); return }
        if (!payload || !Array.isArray(payload.items)) {
          callback([], "Spotify does not make this playlist's songs available to copy. The original was left untouched.")
          return
        }
        var page = Api.normalizePage(payload, function(value) {
          return Api.normalizeTrack(value, 96)
        })
        var combined = collected.concat(page.items)
        if (page.next && combined.length < 10000) {
          root.collectPlaylistForCopy(playlist, page.next, combined, expected, callback)
          return
        }
        if (page.next) {
          callback([], "This playlist is too large to copy safely")
          return
        }
        callback(combined, "")
      })
  }

  function addPlaylistCopyBatches(playlist, uris, offset, expected, callback) {
    if (expected !== host.dataSerial) return
    if (offset >= uris.length) { callback(""); return }
    var batch = uris.slice(offset, Math.min(offset + 100, uris.length))
    host.api.request("POST", "/playlists/" + encodeURIComponent(String(playlist.id)) + "/items",
      null, { uris: batch }, function(status, payload, error) {
        if (expected !== host.dataSerial) return
        if (error) { callback(error); return }
        host.updatePlaylistSnapshot(playlist.id, payload && payload.snapshot_id)
        root.addPlaylistCopyBatches(playlist, uris, offset + batch.length, expected, callback)
      })
  }

  function removeOriginalAfterCopy(original, copy, expected, callback) {
    host.api.request("DELETE", "/me/library", { uris: original.uri }, null,
      function(status, payload, error) {
        if (expected !== host.dataSerial) return
        if (error) {
          root.finishPlaylistConversion("Your copy is ready, but Spotify could not remove the original from your library")
          return
        }
        var next = []
        for (var i = 0; i < host.playlists.length; i++) {
          var candidate = host.playlists[i]
          if (String(candidate.id || "") !== String(original.id || "")) next.push(candidate)
        }
        host.playlists = next
        host.setSavedState(original.uri, false)
        root.finishPlaylistConversion("")
        host.succeed("Your playlist is ready")
        if (typeof callback === "function") callback(copy)
      })
  }

  function makePlaylistYourOwn(playlist, callback) {
    if (!playlist || playlist.type !== "playlist" || !playlist.id || !playlist.uri
        || host.playlistOwned(playlist) || host.playlistActionBusy || !host.currentUserId) return
    var expected = host.dataSerial
    host.playlistActionBusy = true
    host.playlistConversionBusy = true
    host.succeed("")
    host.statusMessage = "Reading " + String(playlist.name || "playlist") + "…"
    root.collectPlaylistForCopy(playlist, "", [], expected, function(items, readError) {
      if (readError) { root.finishPlaylistConversion(readError); return }
      var uris = Api.playlistItemUris(items)
      if (Number(playlist.total || 0) > 0 && uris.length === 0) {
        root.finishPlaylistConversion("Spotify does not make this playlist's songs available to copy. The original was left untouched.")
        return
      }
      host.statusMessage = "Creating your playlist…"
      host.api.request("POST", "/me/playlists", null, {
        name: String(playlist.name || "My playlist").slice(0, 100),
        "public": false,
        description: "Your copy, created with Omarchy Spotify"
      }, function(status, payload, createError) {
        if (expected !== host.dataSerial) return
        if (createError) { root.finishPlaylistConversion(createError); return }
        var copy = Api.normalizePlaylist(payload, 96)
        if (!copy) {
          root.finishPlaylistConversion("Spotify created the playlist, but it could not be opened")
          return
        }
        host.registerPlaylistCopy(copy)
        host.statusMessage = "Copying " + uris.length + (uris.length === 1 ? " item…" : " items…")
        root.addPlaylistCopyBatches(copy, uris, 0, expected, function(copyError) {
          if (copyError) {
            root.finishPlaylistConversion("The new playlist was created, but Spotify stopped before every item was copied. The original was kept.")
            return
          }
          host.statusMessage = "Removing the original from your library…"
          root.removeOriginalAfterCopy(playlist, copy, expected, callback)
        })
      })
    })
  }

  function requestPlaylistItemReorder(sourceIndex, destinationIndex, playlist, count,
      sourceItems) {
    var target = playlist || host.selectedPlaylist
    if (!host.playlistEditable(target) || host.playlistActionBusy) return
    var expected = host.dataSerial
    var length = Math.max(0, Math.floor(Number(count) || host.playlistItems.length))
    var playlistId = String(target.id || "")
    var selectedMatches = host.selectedPlaylist
      && String(host.selectedPlaylist.id || "") === playlistId
    var detailMatches = host.detailItem && host.detailItem.type === "playlist"
      && String(host.detailItem.id || "") === playlistId
    var orderingItems = Array.isArray(sourceItems) ? sourceItems
      : (selectedMatches ? host.playlistItems : (detailMatches ? host.detailItems : []))
    var body = orderingItems.length
      ? Api.playlistReorderBodyForItems(orderingItems, sourceIndex,
        destinationIndex, Math.max(length, Number(target.total) || 0),
        target.snapshotId)
      : Api.playlistReorderBody(sourceIndex, destinationIndex, length,
        target ? target.snapshotId : "")
    if (!body) return

    var sourcePosition = orderingItems.length
      ? Api.playlistPositionAt(orderingItems, sourceIndex) : sourceIndex
    var destinationPosition = orderingItems.length
      ? Api.playlistPositionAt(orderingItems, destinationIndex) : destinationIndex
    var previousPlaylistItems = host.playlistItems
    var previousDetailItems = host.detailItems
    if (selectedMatches)
      host.playlistItems = Api.reorderedPlaylistItemsAtPositions(host.playlistItems,
        sourcePosition, destinationPosition)
    if (detailMatches)
      host.detailItems = Api.reorderedPlaylistItemsAtPositions(host.detailItems,
        sourcePosition, destinationPosition)

    host.playlistActionBusy = true
    host.api.request("PUT", "/playlists/" + encodeURIComponent(String(target.id)) + "/items",
      null, body, function(status, payload, error) {
        if (expected !== host.dataSerial) return
        host.playlistActionBusy = false
        if (error) {
          if (selectedMatches && host.selectedPlaylist
              && String(host.selectedPlaylist.id || "") === playlistId)
            host.playlistItems = previousPlaylistItems
          if (detailMatches && host.detailItem && host.detailItem.type === "playlist"
              && String(host.detailItem.id || "") === playlistId)
            host.detailItems = previousDetailItems
          host.fail(error)
          host.reloadPlaylist(target)
          return
        }
        host.updatePlaylistSnapshot(target.id, payload && payload.snapshot_id)
        host.succeed("Playlist order updated")
      }, { priority: "interactive", retryRateLimit: false })
  }

  function reorderPlaylistItem(sourceIndex, destinationIndex, playlist, count,
      sourceItems) {
    var target = playlist || host.selectedPlaylist
    if (!host.playlistOwned(target)) return
    root.requestPlaylistItemReorder(sourceIndex, destinationIndex, target, count,
      sourceItems)
  }

  function movePlaylistItem(index, delta, playlist, count) {
    var source = Math.max(0, Math.floor(Number(index) || 0))
    var direction = Number(delta || 0) < 0 ? -1 : 1
    root.requestPlaylistItemReorder(source, source + direction,
      playlist || host.selectedPlaylist, count)
  }

}
