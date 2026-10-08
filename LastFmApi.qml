import QtQuick
import "Api.js" as Api

// Public read methods only. Serial, paced requests with bounded caching and
// cancellation. Never log a request URL, API key, or provider error text.
Item {
  id: root
  visible: false
  property string apiKey: ""
  property var xhrFactory: function() { return new XMLHttpRequest() }
  property var now: function() { return Date.now() }
  property int requestTimeoutMs: 15000
  property int paceMs: 350
  property int serial: 0
  property var queue: []
  property var active: null
  property var cache: ({})
  property double cooldownUntil: 0

  onApiKeyChanged: {
    cancelAll()
    cache = ({})
    cooldownUntil = 0
  }

  function cancelAll() {
    serial++
    queue = []
    pace.stop()
    deadline.stop()
    var job = active
    active = null
    if (job && job.xhr) { try { job.xhr.abort() } catch (error) {} }
  }

  function request(method, params, callback, freshnessMs) {
    if (!/^[a-z]+\.get[a-z]+$/i.test(method)) {
      callback(null, "Unsupported Last.fm read method.")
      return
    }
    if (!/^[0-9a-f]{32}$/i.test(apiKey.trim())) {
      callback(null, "Add a valid Last.fm API key in Settings.")
      return
    }
    if (now() < cooldownUntil) {
      callback(null, "Last.fm is limiting requests. Try again in a minute.")
      return
    }
    var query = Object.assign({}, params, { method: method, format: "json" })
    var key = Api.queryString(query)
    var cached = cache[key]
    if (cached && now()-cached.at < (freshnessMs === undefined ? 7*86400000 : freshnessMs)) {
      callback(cached.payload, "")
      return
    }
    queue = queue.concat([{ query: query, key: key, callback: callback, serial: serial }])
    if (!active && !pace.running) pump()
  }

  function finish(job, payload, error) {
    if (job !== active || job.serial !== serial) return
    active = null
    deadline.stop()
    if (!error) {
      var next = Object.assign({}, cache)
      next[job.key] = { payload: payload, at: now() }
      var keys = Object.keys(next).sort(function(a,b) { return next[b].at-next[a].at }).slice(0,256)
      var trimmed = {}
      keys.forEach(function(key) { trimmed[key] = next[key] })
      cache = trimmed
    }
    // Start pacing before callback; a callback may enqueue the next request.
    pace.restart()
    job.callback(payload, error)
  }

  function pump() {
    if (active || !queue.length) return
    var job = queue[0]
    queue = queue.slice(1)
    active = job
    if (now() < cooldownUntil) {
      finish(job, null, "Last.fm is limiting requests. Try again in a minute.")
      return
    }
    try {
      job.xhr = xhrFactory()
      var xhr = job.xhr
      xhr.onreadystatechange = function() {
        if (!root || xhr.readyState !== XMLHttpRequest.DONE || job !== root.active || job.serial !== root.serial) return
        var payload = null
        try { payload = JSON.parse(xhr.responseText) } catch (error) {}
        var code = payload ? Number(payload.error) : 0
        if (xhr.status === 429 || code === 29) {
          var retry = Number(xhr.getResponseHeader("Retry-After")) || 60
          root.cooldownUntil = root.now() + Math.max(60000, retry*1000)
        }
        var message = ""
        if (code === 10 || code === 26) message = "Last.fm rejected the API key. Check it in Settings."
        else if (code === 6 || code === 7) message = "Last.fm could not find that profile or artist."
        else if (xhr.status === 429 || code === 29) message = "Last.fm is limiting requests. Try again in a minute."
        else if (code === 17) message = "This Last.fm profile's recent tracks are private."
        else if (xhr.status < 200 || xhr.status >= 300 || !payload || code)
          message = "Last.fm could not load music data. Try Refresh later."
        root.finish(job, message ? null : payload, message)
      }
      xhr.open("GET", "https://ws.audioscrobbler.com/2.0/?"
        + Api.queryString(Object.assign({}, job.query, { api_key: apiKey.trim() })))
      deadline.restart()
      xhr.send()
    } catch (error) {
      finish(job, null, "Last.fm could not be reached. Try Refresh later.")
    }
  }

  Timer { id: pace; interval: root.paceMs; onTriggered: root.pump() }
  Timer {
    id: deadline
    interval: root.requestTimeoutMs
    onTriggered: {
      var job = root.active
      if (!job) return
      root.finish(job, null, "Last.fm took too long to respond. Try again.")
      try { job.xhr.abort() } catch (error) {}
    }
  }
  Component.onDestruction: cancelAll()
}
