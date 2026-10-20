import QtQuick
import Quickshell
import Quickshell.Io

import "Api.js" as Api

// Private Unix-socket client for the plugin backend. Local load/control uses
// this when the supervised process is running; MPRIS and the Web API remain
// the fallback when the socket is absent or the spotifyd unit is active.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property bool wanted: false
  readonly property var activeSocket: socketLoader.item
  readonly property bool connected: !!(activeSocket && activeSocket.connected)
  property string lifecycle: ""
  property bool sessionConnected: false
  property string errorCode: ""
  property string errorMessage: ""
  property var lastState: null
  property int nextId: 1
  property var pending: ({})
  property int reconnectAttempt: 0
  property bool protocolReady: false
  property var capabilities: ({})
  property var lastQueue: null
  property int requestTimeoutMs: 5000
  readonly property int pendingCount: Object.keys(pending).length

  readonly property string socketPath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return String(runtime || "/tmp") + "/omarchy-spotify/backend.sock"
  }
  readonly property bool ready: connected && protocolReady
    && (lifecycle === "ready" || lifecycle === "")

  signal stateReceived(var state)
  signal queueReceived(var queue)

  function resetPending(reason) {
    var waiters = pending
    pending = ({})
    var message = String(reason || "Playback on this computer is unavailable")
    for (var id in waiters) {
      var callback = waiters[id].callback
      if (typeof callback === "function") {
        try { callback(false, null, message, true) }
        catch (error) { /* consumers own callback errors */ }
      }
    }
  }

  function sendCommand(name, fields, callback) {
    var socket = activeSocket
    if (!socket || !socket.connected || (name !== "hello" && !protocolReady)) {
      if (typeof callback === "function")
        callback(false, null, "Playback on this computer is not ready", false)
      return 0
    }
    if (pendingCount >= 128) {
      if (typeof callback === "function") callback(false, null, "Playback is busy", false)
      return 0
    }
    var id = nextId++
    var payload = { v: 1, id: id, command: String(name || "") }
    Api.assign(payload, fields || {})
    var nextPending = ({})
    for (var existing in pending) nextPending[existing] = pending[existing]
    nextPending[String(id)] = { callback: callback, deadline: Date.now() + requestTimeoutMs }
    pending = nextPending
    socket.write(JSON.stringify(payload) + "\n")
    socket.flush()
    return id
  }

  function loadPlayback(body, callback) {
    var fields = Api.backendLoadFields(body)
    if (!fields) {
      if (typeof callback === "function")
        callback(false, null, "This Spotify item cannot be played")
      return 0
    }
    return sendCommand("load", fields, callback)
  }

  function expirePending(now) {
    var expired = []
    var next = ({})
    for (var id in pending) {
      if (pending[id].deadline <= now) expired.push(pending[id])
      else next[id] = pending[id]
    }
    if (!expired.length) return
    pending = next
    for (var i = 0; i < expired.length; i++) {
      var callback = expired[i].callback
      if (typeof callback === "function") {
        try { callback(false, null, "Playback command timed out; its outcome is unknown", true) }
        catch (error) { /* consumers own callback errors */ }
      }
    }
  }

  function handleLine(line, source) {
    if (source && source !== activeSocket) return
    var message = Api.parseJson(line, null)
    if (!message || typeof message !== "object") return
    if (message.v !== 1 || (message.state && message.state.protocol_version !== 1)) {
      protocolReady = false
      errorMessage = "This playback backend uses an unsupported protocol version"
      resetPending(errorMessage)
      return
    }
    if (message.type === "event" && message.event === "queue_changed") {
      lastQueue = message.queue || null
      queueReceived(lastQueue)
      return
    }
    if (message.type === "event" && message.state) {
      lastState = message.state
      lifecycle = String(message.state.lifecycle || "")
      sessionConnected = message.state.session_connected === true
      errorMessage = Api.redact(String(message.state.error || ""))
      errorCode = String(message.state.error_code || "")
      stateReceived(message.state)
      return
    }
    if (message.type !== "response") return
    var id = String(message.id || "")
    var entry = pending[id]
    if (entry === undefined) return
    var callback = entry.callback
    var nextPending = ({})
    for (var key in pending) if (key !== id) nextPending[key] = pending[key]
    pending = nextPending
    if (typeof callback !== "function") return
    if (message.ok === true) callback(true, message.result || ({}), "")
    else {
      var error = message.error || {}
      callback(false, null, Api.redact(String(error.message
        || "Playback command failed")))
    }
  }

  onWantedChanged: {
    if (wanted) return
    reconnectTimer.stop()
    socketLoader.active = false
    lifecycle = ""
    sessionConnected = false
    errorCode = ""
    errorMessage = ""
    lastState = null
    lastQueue = null
    protocolReady = false
    capabilities = ({})
    reconnectAttempt = 0
    resetPending("Playback on this computer stopped")
  }

  onConnectedChanged: {
    protocolReady = false
    capabilities = ({})
    if (!connected) {
      lifecycle = ""
      sessionConnected = false
      lastState = null
      lastQueue = null
      resetPending("Playback disconnected; the command outcome is unknown")
      return
    }
    reconnectAttempt = 0
    sendCommand("hello", null, function(ok, result, error) {
      root.capabilities = ok && result && result.protocol_version === 1
        ? (result.capabilities || ({})) : ({})
      root.protocolReady = ok && result && result.protocol_version === 1
      if (!root.protocolReady) root.errorMessage = error || "Unsupported playback protocol"
    })
  }

  // No watchdog work when there are no outstanding requests.
  Timer {
    interval: 250
    repeat: true
    running: root.pendingCount > 0
    onTriggered: root.expirePending(Date.now())
  }

  Component {
    id: socketComponent
    Socket {
      id: liveSocket
      path: root.socketPath
      connected: true
      parser: SplitParser {
        splitMarker: "\n"
        onRead: function(line) { root.handleLine(line, liveSocket) }
      }

    }
  }

  Loader {
    id: socketLoader
    active: false
    sourceComponent: socketComponent
  }

  // A failed connect leaves Quickshell's Socket holding a dead QLocalSocket.
  // Setting connected=true again is a no-op, so each retry creates a new Socket.
  Timer {
    id: reconnectTimer
    interval: Math.min(1500, 180 + root.reconnectAttempt * 120)
    repeat: true
    triggeredOnStart: true
    running: root.wanted && !root.connected
    onTriggered: {
      root.reconnectAttempt = Math.min(12, root.reconnectAttempt + 1)
      socketLoader.active = false
      socketLoader.active = true
    }
  }
}
