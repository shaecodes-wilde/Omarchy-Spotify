import QtQuick
import "Api.js" as Api

// Owns queue snapshots, metadata, and sequential mutations for one Service.
Item {
  id: root
  visible: false
  required property var host
  property bool queueLoaded: false
  property bool queueLoading: false
  Connections {
    target: root.host.backend
    function onQueueReceived() {
      if (root.nativeQueueActive) {
        root.renderNativeQueue()
        root.resolveQueueMetadata()
      }
    }
  }
  property var queue: []
  readonly property bool nativeQueueActive: host.backend.ready && !host.useRemotePlayback
    && host.backend.capabilities.queue_snapshot === true
  readonly property string queueSource: nativeQueueActive ? "native" : "web"
  readonly property bool queueCanActivate: false
  readonly property bool queueCanEdit: false
  readonly property string queueUnavailableReason: "Spotify does not expose context-preserving queue jump, reorder, remove, or clear controls for this receiver"
  readonly property string queueContextUri: nativeQueueActive && host.backend.lastQueue
    ? String(host.backend.lastQueue.context_uri || "") : ""
  readonly property string playbackContextUri: nativeQueueActive ? queueContextUri
    : (host.remotePlayback ? String(host.remotePlayback.contextUri || "") : "")
  readonly property bool queueTruncated: nativeQueueActive && host.backend.lastQueue
    ? host.backend.lastQueue.truncated === true : false
  property bool queueActionBusy: false
  property int queueActionSerial: 0
  property int queueRevision: 0
  property var visibleItems: ({})
  property bool metadataBlocked: false
  property var queueMetadata: ({})
  property var queueMetadataOrder: []
  property bool queueMetadataLoading: false
  property var metadataRequest: null
  property int metadataSerial: 0
  readonly property string queuePlaybackIdentity: queueSource + "|" + host.currentUri + "|"
    + host.selectedDeviceId + "|" + (host.remoteDevice ? String(host.remoteDevice.id || host.remoteDevice.name || "") : "")
  onQueuePlaybackIdentityChanged: invalidateQueue()
  function reset() {
    metadataSerial++
    host.api.abortRequest(metadataRequest)
    metadataRequest = null
    queueRevision++
    queueActionSerial++
    queue = []
    queueLoaded = false
    queueLoading = false
    queueMetadata = ({})
    queueMetadataOrder = []
    queueMetadataLoading = false
    queueActionBusy = false
    metadataBlocked = false
    visibleItems = ({})
  }

  function activateQueueItem(item) {
    host.fail(queueUnavailableReason)
  }

  function invalidateQueue() {
    queueRevision++
    queueLoaded = false
    queueLoading = false
    queue = []
    if (nativeQueueActive || host.activeView === "queue" || Object.keys(visibleItems).length) loadQueue()
  }

  function renderNativeQueue() {
    var snapshot = host.backend.lastQueue
    var entries = snapshot && Array.isArray(snapshot.next_tracks) ? snapshot.next_tracks : []
    var next = []
    for (var i = 0; i < entries.length && i < 100; i++) {
      var entry = entries[i]
      var uri = String(entry.uri || "")
      var parts = uri.split(":")
      if (parts.length !== 3 || ["track", "episode"].indexOf(parts[1]) < 0) continue
      var item = queueMetadata["$" + uri]
      if (!item) item = { kind: "item", type: parts[1], id: parts[2], uri: uri,
        name: (parts[1] === "episode" ? "Episode " : "Track ") + parts[2],
        subtitle: "Metadata unavailable", imageUrl: "", durationMs: 0 }
      next.push(item)
    }
    queue = next
    queueLoaded = snapshot !== null
    queueLoading = false
  }

  function setQueueVisibleItems(surfaceId, items) {
    var next = ({})
    for (var key in visibleItems) if (key !== surfaceId) next[key] = visibleItems[key]
    if (Array.isArray(items) && items.length) next[surfaceId] = items.slice(0, 50)
    visibleItems = next
    if (!Object.keys(next).length && queueMetadataLoading) {
      metadataSerial++
      host.api.abortRequest(metadataRequest)
      metadataRequest = null
      queueMetadataLoading = false
    }
    resolveQueueMetadata()
  }

  function resolveQueueMetadata() {
    if (!nativeQueueActive || queueMetadataLoading || metadataBlocked || !host.accountConnected) return
    var missing = []
    var type = ""
    for (var key in visibleItems) {
      var items = visibleItems[key]
      for (var i = 0; i < items.length && missing.length < 50; i++) {
        var item = items[i]
        if (!item || queueMetadata["$" + item.uri] || (type && item.type !== type)
            || ["track", "episode"].indexOf(item.type) < 0) continue
        type = item.type
        if (missing.indexOf(item.id) < 0) missing.push(item.id)
      }
    }
    if (!missing.length) return
    var account = host.dataSerial
    var serial = ++metadataSerial
    queueMetadataLoading = true
    metadataRequest = host.api.request("GET", type === "episode" ? "/episodes" : "/tracks",
      { ids: missing.join(",") }, null, function(status, payload, error) {
        if (account !== root.host.dataSerial || serial !== root.metadataSerial) return
        root.metadataRequest = null
        root.queueMetadataLoading = false
        // Restricted metadata endpoints stay quiet until the account cache resets.
        if (error && [401, 403, 404].indexOf(status) >= 0) root.metadataBlocked = true
        var values = payload && payload[type === "episode" ? "episodes" : "tracks"] || []
        var metadata = root.queueMetadata
        var order = root.queueMetadataOrder.slice()
        for (var j = 0; j < missing.length; j++) {
          var uri = "spotify:" + type + ":" + missing[j]
          var normalized = values[j] ? Api.normalizeTrack(values[j], 96) : null
          metadata["$" + uri] = normalized && normalized.uri === uri ? normalized : {
            kind: "item", type: type, id: missing[j], uri: uri,
            name: (type === "episode" ? "Episode " : "Track ") + missing[j],
            subtitle: "Metadata unavailable", imageUrl: "", durationMs: 0 }
          order.push(uri)
        }
        while (order.length > 200) delete metadata["$" + order.shift()]
        root.queueMetadataOrder = order
        if (root.nativeQueueActive) root.renderNativeQueue()
        root.resolveQueueMetadata()
      }, { retryRateLimit: false })
  }

  function loadQueue(callback, serial) {
    if (nativeQueueActive) {
      renderNativeQueue()
      resolveQueueMetadata()
      if (typeof callback === "function") callback()
      return
    }
    if (queueLoading) {
      if (typeof callback === "function") callback()
      return
    }
    var expected = serial === undefined ? host.dataSerial : serial
    var revision = queueRevision
    queueLoading = true
    host.api.request("GET", "/me/player/queue", null, null,
      function(status, payload, error) {
        if (expected !== root.host.dataSerial || revision !== root.queueRevision || root.nativeQueueActive) return
        root.queueLoading = false
        if (error) root.host.fail(error)
        else {
          var source = payload && Array.isArray(payload.queue) ? payload.queue : []
          var next = []
          for (var i = 0; i < source.length && next.length < 100; i++) {
            var track = Api.normalizeTrack(source[i], 96)
            if (track) next.push(track)
          }
          root.queue = next
          root.queueLoaded = true
        }
        if (typeof callback === "function") callback()
      })
  }

  function addToQueue(item, callback) {
    addItemsToQueue([item], callback)
  }

  function enqueueQueueItem(item, native, deviceId, callback) {
    if (native) {
      host.backend.sendCommand("add_to_queue", { uri: item.uri }, callback)
      return
    }
    host.api.request("POST", "/me/player/queue", {
      uri: item.uri, device_id: deviceId || undefined
    }, null, function(status, payload, error) {
      callback(!error, null, error || "", !!error && status === 0)
    }, { priority: "interactive", retryRateLimit: false })
  }

  function addItemsToQueue(items, callback) {
    var source = Array.isArray(items) ? items.slice() : []
    var error = queueActionBusy ? "A queue action is already running"
      : (!source.length || source.length > 100 ? "Select between 1 and 100 queue items" : "")
    for (var i = 0; !error && i < source.length; i++) {
      var item = source[i]
      if (!item || ["track", "episode"].indexOf(item.type) < 0
          || String(item.uri || "").indexOf("spotify:" + item.type + ":") !== 0)
        error = "Only Spotify tracks and episodes can be added to the queue"
    }
    if (error) {
      host.fail(error)
      if (typeof callback === "function") callback(false, 0, error, false)
      return
    }
    var serial = ++queueActionSerial
    var account = host.dataSerial
    var native = !host.useRemotePlayback && host.backend.ready
    var deviceId = host.controlDeviceId()
    var selection = host.selectedDeviceId
    var added = 0
    var finished = false
    queueActionBusy = true
    host.noteActivity()
    function finish(ok, error, unknown) {
      if (finished) return
      finished = true
      if (serial === root.queueActionSerial) root.queueActionBusy = false
      if (ok) root.host.succeed(added === 1 ? "Added to queue" : "Added " + added + " items to queue")
      else root.host.fail((added ? "Added " + added + " of " + source.length + ". " : "")
        + (error || "Could not add that item to the queue")
        + (unknown ? ". The last item's outcome is unknown; check the queue before trying again" : ""))
      if (added && account === root.host.dataSerial) root.loadQueue()
      if (typeof callback === "function") callback(ok, added, error || "", unknown === true)
    }
    function next() {
      if (serial !== root.queueActionSerial || account !== root.host.dataSerial
          || selection !== root.host.selectedDeviceId || native !== (!root.host.useRemotePlayback && root.host.backend.ready)) {
        finish(false, "The playback device or account changed", false)
        return
      }
      root.enqueueQueueItem(source[added], native, deviceId, function(ok, result, error, unknown) {
        if (!ok) { finish(false, error, unknown); return }
        added++
        if (added === source.length) finish(true, "", false)
        else next()
      })
    }
    next()
  }

}
