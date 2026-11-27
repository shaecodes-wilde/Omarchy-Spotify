import "real" as Real

// The private test runtime supplies the unchanged production client as Real.
Real.BackendClient {
  property var playbackCallback: null
  property var shuffleCallback: null
  property int shuffleRequests: 0
  function sendCommand(name, fields, callback) {
    if (name !== "set_shuffle" || fields.enabled !== false)
      throw new Error("Ordered playback must turn shuffle off")
    shuffleRequests++
    shuffleCallback = callback
    return 1
  }
  function loadPlayback(body, callback) {
    playbackCallback = callback
    return 1
  }
}
