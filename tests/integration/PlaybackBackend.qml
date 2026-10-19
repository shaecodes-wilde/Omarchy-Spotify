import "real" as Real

// The private test runtime supplies the unchanged production client as Real.
Real.BackendClient {
  property var playbackCallback: null
  function loadPlayback(body, callback) {
    playbackCallback = callback
    return 1
  }
}
