import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Plugin

ShellRoot {
  id: tests
  property int step: 0
  QtObject {
    id: fakeHost
    property var settings: ({ lastFmUsername: "profile", lastFmApiKey: "0123456789abcdef0123456789abcdef" })
    property bool accountConnected: true
    property string currentUserId: "account-one"
    property string stateDir: Quickshell.env("XDG_STATE_HOME") + "/persistence"
    property var api: null
  }
  Plugin.DiscoveryController { id: discovery; host: fakeHost }
  FileView {
    id: reader
    path: ""
    printErrors: false
    onLoaded: {
      var saved = JSON.parse(text())
      if (saved.version !== 3 || saved.scope !== "profile|account-one" || saved.history["$heard"] !== 1800000000
          || saved.audience["$a"].source !== "lastfm-artist-total" || saved.audience["$a"].listeners !== 123
          || saved.feedback["$feedback"].rating !== "more" || text().indexOf(fakeHost.settings.lastFmApiKey) >= 0)
        throw new Error("Discovery persistence content or credential isolation failed")
      fakeHost.currentUserId = "account-two"
      tests.step = 2
    }
    onLoadFailed: retry.start()
  }
  Timer { id: retry; interval: 20; onTriggered: reader.reload() }
  Timer {
    interval: 20
    repeat: true
    running: true
    property int ticks: 0
    onTriggered: {
      ticks++
      if (ticks > 200) throw new Error("Discovery persistence timed out")
      if (!discovery.storeReady) return
      if (tests.step === 0) {
        discovery.history = { "$heard": 1800000000 }
        discovery.feedback = { "$feedback": { artist: "A", rating: "more", at: Date.now() } }
        discovery.audienceProvider.cache = { "$a": { artistKey: "$a", name: "A", listeners: 123,
          at: Date.now(), source: "lastfm-artist-total" } }
        discovery.writeState()
        tests.step = 1
        reader.path = discovery.storagePath
      } else if (tests.step === 2) {
        if (Object.keys(discovery.history).length || Object.keys(discovery.feedback).length
            || Object.keys(discovery.audienceProvider.cache).length)
          throw new Error("Different account inherited private discovery state")
        fakeHost.currentUserId = "account-one"
        tests.step = 3
      } else if (tests.step === 3) {
        if (discovery.history["$heard"] !== 1800000000 || discovery.feedback["$feedback"].rating !== "more"
            || !discovery.audienceProvider.fresh(discovery.audienceProvider.cache["$a"], "A"))
          throw new Error("Original account did not restore its cache")
        console.log("DISCOVERY_PERSISTENCE_PASS")
        Qt.quit()
      }
    }
  }
}
