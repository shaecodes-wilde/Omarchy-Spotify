import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  id: testCase
  property var requests: []
  property string uri: "spotify:track:example"
  function check(value, message) { if (!value) throw new Error(message) }
  Plugin.Service {
    id: service
    function ensureVisibleLocalReceiver() {}
    function syncCurrentTrackSaved(force) {}
  }
  function xhr() {
    var value = { readyState: 0, status: 0, responseText: "", onreadystatechange: null,
      open: function(method, url) { this.method = method; this.url = url },
      send: function() {}, setRequestHeader: function() {},
      getResponseHeader: function(name) { return "" }, abort: function() {} }
    requests.push(value)
    return value
  }
  function complete(index, payload) {
    var value = requests[index]
    value.status = 200
    value.responseText = JSON.stringify(payload)
    value.readyState = XMLHttpRequest.DONE
    value.onreadystatechange()
  }
  function page(offset) {
    var items = []
    for (var i = offset; i < offset + 30; i++) items.push({ track: {
      type: "track", id: String(i), uri: "spotify:track:" + i, name: "Track " + i
    } })
    return { items: items, next: "https://api.spotify.com/v1/me/tracks?offset=" + (offset + 30) }
  }
  Timer {
    interval: 50
    running: true
    onTriggered: {
      // Keep the valid default identity; all HTTP uses the injected transport below.
      service.auth.accessToken = "test-token"
      service.auth.accessTokenExpiresAt = Date.now() + 3600000
      service.auth.loggedIn = true
      service.api.xhrFactory = testCase.xhr
      service.visibleSurfaces = { test: true }
      service.activeView = "library"
      service.activeLibraryKind = "tracks"
      service.requestContains([testCase.uri], service.dataSerial)
      service.toggleSavedItems([{ type: "track", uri: testCase.uri }])
      complete(1, {})
      complete(0, [false])
      check(service.isSaved({ uri: testCase.uri }), "Late contains reply undid confirmed save")
      service.requestContains([testCase.uri], service.dataSerial)
      service.toggleSavedItems([{ type: "track", uri: testCase.uri }])
      complete(3, {})
      complete(2, [true])
      check(!service.isSaved({ uri: testCase.uri }), "Late contains reply undid confirmed removal")

      service.loadLibrary("tracks", false, true)
      service.ensureLibraryItemCount("tracks", 75)
      check(service.libraryRestorePending("tracks"), "Missing initial restore target")
      complete(4, page(0))
      complete(5, page(30))
      complete(6, page(60))
      check(service.savedTracks.length === 90 && !service.libraryRestorePending("tracks"), "Restore stopped before target")
      service.ensureLibraryItemCount("tracks", 150)
      var pending = requests.length - 1
      service.visibleSurfaces = ({})
      complete(pending, page(90))
      check(requests.length === pending + 1, "Hidden restore scheduled another page")
      check(!service.libraryRestorePending("tracks"), "Hidden restore target remained active")
      console.log("LIBRARY_STATE_PASS")
      Qt.quit()
    }
  }
}
