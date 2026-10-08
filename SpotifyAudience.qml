import QtQuick
import "Discovery.js" as Discovery

// Public artist HTML only: no bearer tokens, private endpoints or browser.
Item {
  id: root
  visible: false
  property var xhrFactory: function() { return new XMLHttpRequest() }
  property var now: function() { return Date.now() }
  property int paceMs: 500
  property int requestTimeoutMs: 10000
  property var cache: ({})
  property var queue: []
  property var active: null
  property int serial: 0
  property double cooldownUntil: 0

  function fresh(record, artistId) {
    return record && record.artistId === artistId && Discovery.validCount(record.listeners)
      && record.source === "spotify-public-artist-page" && record.at > 0
      && record.at <= now() && now()-record.at < 86400000
  }

  function cancelAll() {
    serial++; queue = []; pace.stop(); deadline.stop()
    var job = active; active = null
    if (job && job.xhr) { try { job.xhr.abort() } catch (error) {} }
  }

  function request(artistId, callback) {
    if (!/^[A-Za-z0-9]{22}$/.test(artistId)) { callback(null,"","unknown"); return }
    var record = cache[artistId]
    if (fresh(record,artistId)) { callback(record,"",""); return }
    if (now() < cooldownUntil) {
      callback(null,"Spotify is limiting monthly listener checks. Try Refresh later.","unavailable")
      return
    }
    queue = queue.concat([{ artistId: artistId, callback: callback, serial: serial }])
    if (!active && !pace.running) pump()
  }

  function finish(job, record, error, reason) {
    if (job !== active || job.serial !== serial) return
    active = null; deadline.stop()
    if (record) {
      var next = Object.assign({},cache); next[job.artistId] = record
      cache = Discovery.boundedMap(next,400)
    }
    pace.restart()
    job.callback(record,error,reason)
  }

  function pump() {
    if (active || !queue.length) return
    var job = queue[0]; queue = queue.slice(1); active = job
    if (now() < cooldownUntil) {
      finish(job,null,"Spotify is limiting monthly listener checks. Try Refresh later.","unavailable")
      return
    }
    try {
      job.xhr = xhrFactory()
      var xhr = job.xhr
      xhr.onreadystatechange = function() {
        if (!root || xhr.readyState !== XMLHttpRequest.DONE || job !== root.active || job.serial !== root.serial) return
        if (xhr.status === 429) {
          var retry = Number(xhr.getResponseHeader("Retry-After")) || 60
          root.cooldownUntil = root.now() + Math.max(60000,retry*1000)
          root.finish(job,null,"Spotify is limiting monthly listener checks. Try Refresh later.","unavailable")
        } else if (xhr.status === 404) root.finish(job,null,"","unknown")
        else if (xhr.status !== 200) root.finish(job,null,
          "Spotify monthly listener counts are unavailable. Try Refresh later.","unavailable")
        else {
          var count = Discovery.parseAudience(xhr.responseText,job.artistId)
          root.finish(job,count === null ? null : { artistId: job.artistId, listeners: count,
            at: root.now(), source: "spotify-public-artist-page" },"",count === null ? "unknown" : "")
        }
      }
      xhr.open("GET","https://open.spotify.com/artist/"+job.artistId)
      xhr.setRequestHeader("Accept-Language","en-US,en;q=0.9")
      xhr.setRequestHeader("User-Agent","Mozilla/5.0")
      deadline.restart(); xhr.send()
    } catch (error) {
      finish(job,null,"Spotify monthly listener counts could not be reached. Try Refresh later.","unavailable")
    }
  }
  Timer { id: pace; interval: root.paceMs; onTriggered: root.pump() }
  Timer {
    id: deadline
    interval: root.requestTimeoutMs
    onTriggered: {
      var job = root.active
      if (!job) return
      root.finish(job,null,"Spotify monthly listener checks timed out. Try Refresh later.","unavailable")
      try { job.xhr.abort() } catch (error) {}
    }
  }
  Component.onDestruction: cancelAll()
}
