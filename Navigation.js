.pragma library

var HISTORY_LIMIT = 20
var SESSION_LIMIT = 15500
var TABS = ["home", "discover", "search", "library", "playlists", "detail", "queue", "devices", "setup"]
var TEXT_FIELDS = ["searchText", "searchType", "libraryType", "homeType", "libraryFilter", "librarySort",
  "playlistFilter", "playlistSort", "detailFilter", "detailSort", "homeFilter", "discoverFilter",
  "queueFilter", "artistSearchText", "selectedPlaylistId", "focusRegion", "focusAction"]

function context(item) {
  if (!item || !item.id || ["album", "artist", "playlist", "show", "audiobook"].indexOf(item.type) < 0) return null
  var result = { id: String(item.id).slice(0, 128), type: item.type, kind: "context" }
  var fields = ["name", "subtitle", "uri", "imageUrl", "description", "ownerId"]
  for (var i = 0; i < fields.length; i++)
    if (item[fields[i]] !== undefined) result[fields[i]] = String(item[fields[i]]).slice(0, 512)
  result.collaborative = item.collaborative === true
  return result
}

function count(value) { return Math.min(10000, Math.max(0, Math.floor(Number(value) || 0))) }

function positions(value, limit) {
  var source = value && typeof value === "object" ? value : ({})
  var keys = Object.keys(source).slice(-(limit || 128))
  var result = ({})
  for (var i = 0; i < keys.length; i++)
    result[String(keys[i]).slice(0, 180)] = Math.min(10000000, Math.max(0, Number(source[keys[i]]) || 0))
  return result
}

// Both history and the session use this route shape; never retain result arrays.
function snapshot(source) {
  var value = source || ({})
  var result = { tab: TABS.indexOf(value.tab) >= 0 ? value.tab : "home" }
  for (var i = 0; i < TEXT_FIELDS.length; i++) {
    var name = TEXT_FIELDS[i]
    if (value[name] !== undefined) result[name] = String(value[name]).slice(0, 512)
  }
  result.detailItem = context(value.detailItem || value.item)
  result.selectedPlaylist = context(value.selectedPlaylist)
  result.detailItemCount = count(value.detailItemCount)
  result.selectedPlaylistItemCount = count(value.selectedPlaylistItemCount)
  result.focusActive = value.focusActive === true
  result.universalSearchActive = value.universalSearchActive === true
  result.searchInContext = value.searchInContext !== false
  result.focusIndex = Math.max(-1, Math.min(10000, Math.floor(Number(value.focusIndex) || 0)))
  result.scrollPositions = positions(value.scrollPositions, 8)
  return result
}

function push(history, route) {
  return (Array.isArray(history) ? history : []).concat([snapshot(route)]).slice(-HISTORY_LIMIT)
}

function pins(value) {
  var result = []
  var values = Array.isArray(value) ? value : []
  for (var i = 0; i < values.length && result.length < 32; i++) {
    var id = String(values[i] || "").slice(0, 128)
    if (id && result.indexOf(id) < 0) result.push(id)
  }
  return result
}

function pinnedPlaylists(items, pinnedIds) {
  var pinned = pins(pinnedIds)
  var values = Array.isArray(items) ? items : []
  return values.filter(function(item) { return pinned.indexOf(item.id) >= 0 })
    .concat(values.filter(function(item) { return pinned.indexOf(item.id) < 0 }))
}

function session(source, back, forward) {
  var result = snapshot(source)
  result.scrollPositions = positions(source.scrollPositions, 128)
  result.sidebarWidth = Math.max(176, Math.min(360, Number(source.sidebarWidth) || 214))
  result.sidebarCollapsed = source.sidebarCollapsed === true
  result.playlistPins = pins(source.playlistPins)
  result.lastRadioPlaylist = context(source.lastRadioPlaylist)
  result.backHistory = (Array.isArray(back) ? back : []).slice(-HISTORY_LIMIT).map(snapshot)
  result.forwardHistory = (Array.isArray(forward) ? forward : []).slice(-HISTORY_LIMIT).map(snapshot)
  while (JSON.stringify(result).length > SESSION_LIMIT && (result.backHistory.length || result.forwardHistory.length)) {
    if (result.backHistory.length >= result.forwardHistory.length) result.backHistory.shift()
    else result.forwardHistory.shift()
  }
  // Filters/scroll are bounded too, so oversized artwork/description metadata cannot drop the session.
  if (JSON.stringify(result).length > SESSION_LIMIT) {
    result.scrollPositions = positions(result.scrollPositions, 16)
    for (var f = 0; f < TEXT_FIELDS.length; f++) {
      var field = TEXT_FIELDS[f]
      if (result[field]) result[field] = result[field].slice(0, 256)
    }
    var contexts = [result.detailItem, result.selectedPlaylist, result.lastRadioPlaylist]
    for (var c = 0; c < contexts.length; c++) {
      if (!contexts[c]) continue
      contexts[c].description = String(contexts[c].description || "").slice(0, 128)
      contexts[c].subtitle = String(contexts[c].subtitle || "").slice(0, 128)
    }
  }
  return result
}

function spotifyLink(text) {
  var value = String(text || "").trim()
  var match = /^spotify:(album|artist|playlist|show|audiobook|track|episode):([A-Za-z0-9]+)$/.exec(value)
  if (!match) match = /^https:\/\/open\.spotify\.com\/(?:intl-[a-z]+\/)?(album|artist|playlist|show|audiobook|track|episode)\/([A-Za-z0-9]+)(?:[?#].*)?$/.exec(value)
  if (!match) return null
  return { id: match[2], type: match[1], kind: ["track", "episode"].indexOf(match[1]) >= 0 ? "item" : "context",
    uri: "spotify:" + match[1] + ":" + match[2], name: "Spotify " + match[1] }
}
