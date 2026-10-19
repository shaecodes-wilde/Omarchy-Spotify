import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  id: tests
  property var calls: []
  property var replies: []
  Plugin.Service { id: service }
  Plugin.QueueController {
    id: queueTest
    host: service
    function enqueueQueueItem(item, native, device, callback) {
      tests.calls.push(item.uri)
      tests.replies.push(callback)
    }
  }
  property var metadataCalls: []
  property var metadataReplies: []
  QtObject {
    id: fakeApi
    function abortRequest(handle) {}
    function request(method, path, query, body, callback) {
      tests.metadataCalls.push(query ? query.ids : "web-queue")
      tests.metadataReplies.push(callback)
    }
  }
  QtObject {
    id: fakeBackend
    property bool ready: true
    property var capabilities: ({queue_snapshot: true})
    property var lastQueue: ({next_tracks: [
      {uri:"spotify:track:visible"}, {uri:"spotify:track:hidden"}]})
    signal queueReceived(var queue)
  }
  QtObject {
    id: metadataHost
    property var api: fakeApi
    property var backend: fakeBackend
    property bool useRemotePlayback: false
    property bool accountConnected: true
    property int dataSerial: 1
    property string currentUri: ""
    property string selectedDeviceId: ""
    property var remoteDevice: null
    property var remotePlayback: null
    property string activeView: "home"
    property bool uiVisible: false
  }
  Plugin.QueueController { id: metadataTest; host: metadataHost }
  Timer {
    interval: 20
    running: true
    onTriggered: {
      service.activeView = "search"
      service.queue = [{ uri: "spotify:track:old" }]
      service.queueLoaded = true
      var revision = service.queueRevision
      service.selectedDeviceId = "another-device"
      if (service.queueLoaded || service.queue.length || service.queueRevision <= revision)
        throw new Error("Device change retained a stale queue")
      service.backend.handleLine(JSON.stringify({ type: "event", v: 1,
        event: "queue_changed", queue: { context_uri: "spotify:playlist:context",
          next_tracks: [ { uri: "spotify:track:repeat", provider: "queue" },
            { uri: "spotify:track:repeat", provider: "context" },
            { uri: "spotify:episode:episode", provider: "context" } ] } }))
      service.renderNativeQueue()
      if (service.queue.length !== 3 || service.queue[0].uri !== service.queue[1].uri
          || service.queue[2].type !== "episode" || !service.queueLoaded)
        throw new Error("Authoritative queue lost duplicate entries or episode identity")
      if (service.queueCanActivate || service.queueCanEdit)
        throw new Error("Unsupported queue controls were advertised")
      var before = service.radioSerial
      service.activateQueueItem(service.queue[1])
      if (service.radioSerial !== before || service.pendingPlaybackBody)
        throw new Error("Queue activation reconstructed the playback context")
      service.backend.handleLine(JSON.stringify({type: "event", v: 1, event: "queue_changed", queue: null}))
      service.renderNativeQueue()
      if (service.queue.length || service.queueLoaded)
        throw new Error("Disconnected queue was retained")
      var callbacks = 0
      queueTest.addItemsToQueue([{type:"track",uri:"spotify:track:first"},
        {type:"track",uri:"spotify:track:first"}, {type:"episode",uri:"spotify:episode:last"}],
        function(ok, added, error, unknown) {
          callbacks++
          if (ok || added !== 1 || !unknown) throw new Error("Queue partial outcome was lost")
        })
      if (!queueTest.queueActionBusy || tests.calls.length !== 1)
        throw new Error("Batch queue did not begin sequentially")
      queueTest.addToQueue({type:"track",uri:"spotify:track:duplicate"})
      if (tests.calls.length !== 1) throw new Error("Rapid duplicate action was dispatched")
      tests.replies[0](true, {}, "", false)
      if (tests.calls.length !== 2 || tests.calls[1] !== tests.calls[0])
        throw new Error("Intentional duplicate was lost or queue order changed")
      tests.replies[1](false, null, "Disconnected", true)
      tests.replies[1](false, null, "Disconnected", true)
      if (tests.calls.length !== 2 || callbacks !== 1 || queueTest.queueActionBusy)
        throw new Error("Uncertain queue action retried or completed more than once")
      if (tests.metadataCalls.length) throw new Error("Hidden queue requested metadata")
      metadataTest.setQueueVisibleItems("pane", [{type:"track",id:"visible",uri:"spotify:track:visible"}])
      if (tests.metadataCalls.join() !== "visible") throw new Error("Hidden metadata was included in batch")
      metadataTest.setQueueVisibleItems("pane", [])
      tests.metadataReplies[0](200, {tracks:[{type:"track",id:"visible",uri:"spotify:track:visible",name:"Visible"}]}, "")
      if (tests.metadataCalls.length !== 1) throw new Error("Hidden metadata chain continued")
      metadataTest.setQueueVisibleItems("pane", [{type:"track",id:"hidden",uri:"spotify:track:hidden"}])
      tests.metadataReplies[1](403, null, "Restricted metadata endpoint")
      fakeBackend.queueReceived(fakeBackend.lastQueue)
      metadataTest.setQueueVisibleItems("pane", [{type:"track",id:"another",uri:"spotify:track:another"}])
      if (tests.metadataCalls.length !== 2 || metadataTest.queue[1].kind !== "item")
        throw new Error("Restricted endpoint retried or native placeholder lost item kind")
      metadataTest.setQueueVisibleItems("pane", [])
      metadataHost.activeView = "queue"
      fakeBackend.ready = false
      metadataHost.selectedDeviceId = "changed-while-hidden"
      if (tests.metadataCalls.length !== 2)
        throw new Error("Hidden Web queue refreshed after playback identity changed")
      console.log("QUEUE_STATE_PASS")
      Qt.quit()
    }
  }
}
