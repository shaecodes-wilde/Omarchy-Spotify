import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  QtObject {
    id: playbackAuth
    function withAccessToken(callback) { callback("test-token", "") }
  }

  function testHiddenGemsPlayback() {
    var service = spotifyService
    service.backend.wanted = false
    var collection = panel.pageCollection()
    check(!!collection, "Hidden gems collection is missing")
    var ancestor = collection.parent
    var button = null
    while (ancestor && !button) {
      button = panel.findNamedItem(ancestor, "gem-play")
      ancestor = ancestor.parent
    }
    check(!!button, "Hidden gems play button is missing")
    check(!button.enabled && panel.pageCursorActions().indexOf("gem-play") < 0,
      "Empty gems should not be playable")
    var calls = []
    service.api.auth = playbackAuth
    service.api.xhrFactory = function() {
      var xhr = {
        readyState: 0, status: 0, responseText: "", url: "", body: null,
        open: function(method, url) { this.url = url },
        setRequestHeader: function() {}, getResponseHeader: function() { return "" },
        abort: function() {},
        send: function(body) { this.body = body ? JSON.parse(body) : null; calls.push(this) },
        respond: function(status, payload) {
          this.status = status
          this.responseText = JSON.stringify(payload || {})
          this.readyState = XMLHttpRequest.DONE
          this.onreadystatechange()
        }
      }
      return xhr
    }
    service.devices = [{ id: "test-device", local: false, active: true, restricted: false }]
    service.selectedDeviceId = "test-device"
    service.selectedDeviceExplicit = true
    service.remotePlaybackLoading = false
    var rows = [
      { kind: "item", type: "track", name: "Other", uri: "spotify:track:other" },
      { kind: "item", type: "track", name: "Match one", uri: "spotify:track:one" },
      { kind: "item", type: "track", name: "Match two", uri: "spotify:track:two" }
    ]
    service.discovery.items = rows
    panel.homeFilter = "Match"
    check(button.enabled && panel.pageCursorActions().indexOf("gem-play") >= 0,
      "Matching gems should enable mouse and keyboard playback")
    button.clicked()
    check(calls.length === 1 && calls[0].url.indexOf("/me/player/shuffle?") >= 0
      && calls[0].url.indexOf("state=false") >= 0 && calls[0].url.indexOf("device_id=test-device") >= 0,
      "Shuffle must be disabled on the playback target before playing")
    calls[0].respond(204)
    check(calls.length === 2 && calls[1].url.indexOf("/me/player/play?") >= 0
      && JSON.stringify(calls[1].body.uris) === JSON.stringify([rows[1].uri, rows[2].uri]),
      "Play button did not play all filtered gems from the top in displayed order")
    check(!service.pendingPlaybackOrdered, "Ordered flag leaked after dispatch")
    service.api.cancelAll()
    calls = []
    service.discovery.loading = true
    panel.playHiddenGems()
    check(!button.enabled && !calls.length && panel.pageCursorActions().indexOf("gem-play") < 0,
      "Refreshing gems should not be playable")
    service.discovery.loading = false
    panel.homeFilter = "No matching tracks"
    panel.playHiddenGems()
    check(!button.enabled && !calls.length, "An empty filter should not play stale results")
    panel.homeFilter = "Match"
    panel.panelCursorRegion = "page"
    panel.panelCursorAction = "gem-play"
    panel.activatePanelCursor()
    check(calls.length === 1, "Keyboard gem playback did not activate")
    calls[0].respond(403, { error: { message: "Shuffle is unavailable" } })
    check(calls.length === 1 && service.lastError.indexOf("Shuffle is unavailable") >= 0,
      "Shuffle failure should be reported without starting unordered playback")

    calls = []
    service.playItem(rows[1], rows.slice(1), "")
    check(calls.length === 1 && calls[0].url.indexOf("/me/player/play?") >= 0,
      "Existing playback should retain its shuffle behavior")
    service.api.cancelAll()
    calls = []
    service.playItem(rows[1], rows.slice(1), "", "", null, true)
    service.radioSerial++
    calls[0].respond(204)
    check(calls.length === 1, "An obsolete shuffle response must not replace newer playback")

    calls = []
    service.pendingPlaybackBody = { uris: [rows[1].uri, rows[2].uri] }
    service.pendingPlaybackOrdered = true
    service.pendingPlaybackSerial = service.radioSerial
    service.sendLocalSocketPlayback(service.pendingPlaybackSerial)
    check(calls.length === 1 && calls[0].url.indexOf("/me/player/shuffle?") >= 0,
      "Local socket failure must retain ordered playback in the Web API fallback: " + calls.length)
    service.api.cancelAll()
  }

  function testPlaylistOccurrenceRemoval() {
    var playlist = { id: "playlist", type: "playlist" }
    var track = { uri: "spotify:track:dup", playlistPosition: 7, playlistSnapshot: "revision" }
    var sent = []
    var reloads = 0
    var lastError = ""
    playlistActions.host = {
      dataSerial: 1, playlistActionBusy: false,
      playlistEditable: function() { return true },
      updatePlaylistSnapshot: function() {},
      reloadPlaylist: function() { reloads++ },
      fail: function(error) { lastError = error },
      succeed: function() {},
      api: { request: function(method, path, query, body, callback) {
        sent.push({ method, path, body, callback })
      }}
    }
    playlistActions.removeOccurrence(track, playlist)
    check(sent.length === 1 && sent[0].method === "DELETE", "Single removal did not use DELETE")
    check(JSON.stringify(sent[0].body) === JSON.stringify({
      items: [{ uri: track.uri, positions: [7] }], snapshot_id: "revision"
    }), "Single removal did not specify the exact occurrence and revision")
    sent[0].callback(409, null, "Playlist changed")
    check(reloads === 1 && lastError === "Playlist changed", "Stale removal should reload the playlist")
    playlistActions.removeOccurrence({ uri: track.uri, playlistPosition: 7 }, playlist)
    check(sent.length === 1 && reloads === 2, "A row without a revision must reload before removal")
  }

  function testDeviceVolumeMemory() {
    var service = spotifyService
    var first = { id: "first", name: "Living room" }
    var second = { id: "second", name: "Office" }
    service.rememberRemoteVolume(first, 24, 20)
    service.rememberRemoteVolume(first, 80, 10)
    check(service.lastAudibleVolumes["id:first"] === 0.24,
      "An older receiver report must not overwrite volume memory")
    service.rememberRemoteVolume(second, 68, 30)
    service.rememberRemoteVolume(second, 0, 40)
    check(service.lastAudibleVolumes["id:first"] === 0.24
      && service.lastAudibleVolumes["id:second"] === 0.68,
      "Each device must retain its own last audible volume")
  }

  Plugin.PlaylistActions { id: playlistActions; host: null }

  QtObject {
    id: scopedShell
    property var barConfig: ({ layout: { left: [{ id: "quickshell.spotify",
      clientId: "invalid", signInMethod: "Web API", deviceName: "Scoped receiver" }] } })
  }
  Plugin.Service { settings: normalizedSettings({ signInMethod: "Web API" }); id: spotifyService }
  Plugin.Panel { id: panel; service: spotifyService; width: 1280; height: 800 }
  Plugin.BarWidget { id: widget }
  Timer {
    interval: 20
    running: true
    onTriggered: {
      spotifyService.auth.customClientId = "invalid"
      if (spotifyService.normalizedSettings({discoveryObscurity:"Balanced"}).discoveryObscurity !== "Obscure"
          || spotifyService.normalizedSettings({}).discoveryObscurity !== "Obscure")
        throw new Error("Discovery default or legacy setting migration failed")
      spotifyService.search("smoke-test", "track")
      if (spotifyService.searchLoading || !spotifyService.searchError)
        throw new Error("Search service did not return the authorization error")
      if (!panel.primaryNavigationItems().some(function(item) { return item.id === "search" }))
        throw new Error("Search navigation is missing")
      spotifyService.clearSearch()
      if (spotifyService.searchQuery !== "") throw new Error("Search state did not clear")
      spotifyService.topTracks = [{ id: "song", albumItem: {
        type: "album", id: "album", uri: "spotify:album:album", name: "Album"
      } }]
      if (spotifyService.homeItems("albums").length !== 1)
        throw new Error("Top albums did not update from top songs")
      if (typeof panel !== "undefined") {
        spotifyService.sessionState = { homeType: "albums" }
        panel.restoreUiState()
        if (panel.homeType !== "albums" || panel.pageCursorActions().indexOf("home-albums") < 0)
          throw new Error("Top albums navigation or restoration is missing")
      }
      spotifyService.shell = scopedShell
      spotifyService.syncSettings()
      if (spotifyService.settings.clientId !== "invalid"
          || spotifyService.deviceName !== "Scoped receiver")
        throw new Error("Scoped shell settings did not load")
      scopedShell.barConfig = { layout: { left: [{ id: "quickshell.spotify",
        clientId: "invalid", signInMethod: "Web API", deviceName: "Updated receiver" }] } }
      spotifyService.sessionState = { homeType: "gems" }
      panel.restoreUiState()
      if (panel.homeType !== "gems" || panel.pageCursorActions().indexOf("home-gems") < 0)
        throw new Error("Hidden gems restoration or navigation is missing")
      panel.currentTab = "setup"
      finishSmoke.start()
    }
  }
  Timer {
    id: finishSmoke
    interval: 20
    onTriggered: {
      if (spotifyService.deviceName !== "Updated receiver")
        throw new Error("Scoped shell settings did not update live")
      panel.currentTab = "home"
      panel.homeType = "gems"
      panel.opened = true
      finishUi.start()
    }
  }
  Timer {
    id: finishUi
    interval: 100
    onTriggered: {
      var status = JSON.parse(panel.discoveryStatus())
      if (!status.available || status.apiKeyConfigured || status.homeType !== "gems"
          || status.listenerMetric !== "Last.fm total listeners" || status.listenerCeiling !== 200000)
        throw new Error("Discovery diagnostics or home page did not load")
      testHiddenGemsPlayback()
      testPlaylistOccurrenceRemoval()
      testDeviceVolumeMemory()
      console.log("APP_SMOKE_PASS")
      Qt.quit()
    }
  }
}
