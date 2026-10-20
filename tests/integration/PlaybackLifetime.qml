import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  id: tests
  property int fallbacks: 0
  property int queueLoads: 0
  property int stateLoads: 0
  Plugin.Service {
    id: service
    function sendPendingPlayback(deviceId) { tests.fallbacks++ }
    function loadQueue(callback, serial) { tests.queueLoads++ }
    function loadPlaybackState(callback, reportError) { tests.stateLoads++ }
  }
  function prepare(serial, message) {
    service.radioSerial = serial
    service.pendingPlaybackSerial = serial
    service.pendingPlaybackBody = { uris: ["spotify:track:" + message] }
    service.pendingPlaybackMessage = message
  }
  Timer {
    interval: 20
    running: true
    onTriggered: {
      prepare(10, "First")
      service.sendLocalSocketPlayback(10)
      var first = service.backend.playbackCallback
      prepare(11, "Second")
      var newer = service.pendingPlaybackBody
      first(false, null, "Known rejection", false)
      if (service.pendingPlaybackBody !== newer || service.pendingPlaybackSerial !== 11 || tests.fallbacks)
        throw new Error("Rejected old load consumed a newer pending play")
      first(true, {}, "", false)
      first(false, null, "Outcome unknown", true)
      if (tests.queueLoads || tests.stateLoads || service.lastError)
        throw new Error("Stale load changed playback UI or dispatched follow-up work")
      service.sendLocalSocketPlayback(11)
      var second = service.backend.playbackCallback
      service.dataSerial++
      second(true, {}, "", false)
      second(false, null, "Old account", false)
      if (tests.queueLoads || tests.stateLoads || tests.fallbacks || service.pendingPlaybackBody)
        throw new Error("Old-account load affected the new session")
      prepare(12, "Newest")
      service.sendLocalSocketPlayback(12)
      service.backend.playbackCallback(true, {}, "", false)
      if (tests.queueLoads !== 1 || tests.stateLoads !== 1 || service.statusMessage !== "Newest")
        throw new Error("Current load did not complete normally")
      console.log("PLAYBACK_LIFETIME_PASS")
      Qt.quit()
    }
  }
}
