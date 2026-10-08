import QtQuick
import "Discovery.js" as Discovery

// Share the existing paced Last.fm transport. Total unique listeners are
// scoped to a Last.fm artist profile/name, not a Spotify ID or monthly window.
Item {
  id: root
  visible: false
  required property var api
  property var now: function() { return Date.now() }
  property var cache: ({})
  property int serial: 0

  function fresh(record, artistName) {
    return record && Discovery.nameKey(artistName)
      && record.artistKey === Discovery.artistKey(artistName)
      && Discovery.validCount(record.listeners) && record.source === "lastfm-artist-total"
      && record.at > 0 && record.at <= now() && now()-record.at < 86400000
  }

  function cancelAll() { serial++ }

  function request(artistName, callback) {
    artistName = Discovery.text(artistName)
    if (!artistName) { callback(null,"","unknown"); return }
    var key = Discovery.artistKey(artistName), cached = cache[key]
    if (fresh(cached,artistName)) { callback(cached,"",""); return }
    var token = serial
    api.request("artist.getInfo",{ artist: artistName, autocorrect: 0 },function(payload,error) {
      if (!root || token !== root.serial) return
      if (error) {
        if (error === "Last.fm could not find that profile or artist.") callback(null,"","unknown")
        else callback(null,error,"unavailable")
        return
      }
      var count = Discovery.lastFmListenerCount(payload,artistName)
      if (count === null) { callback(null,"","unknown"); return }
      var record = { artistKey: key, name: artistName, listeners: count,
        at: root.now(), source: "lastfm-artist-total" }
      var next = Object.assign({},root.cache); next[key] = record
      root.cache = Discovery.boundedMap(next,400)
      callback(record,"","")
    },86400000)
  }
  Component.onDestruction: cancelAll()
}
