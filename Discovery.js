.pragma library

// Deterministic ranking over metadata. No audio analysis or model training.
function list(value) {
  if (!value) return []
  return Array.isArray(value) ? value : [value]
}

function text(value) {
  return String(value && typeof value === "object" ? value["#text"] || value.name || "" : value || "").trim()
}

function nameKey(value) {
  return text(value).toLowerCase().normalize("NFKC").replace(/[’‘]/g, "'")
    .replace(/\s+/g, " ").trim()
}

function trackKey(artist, title) { return "$" + nameKey(artist) + "\u001f" + nameKey(title) }
function artistKey(artist) { return "$" + nameKey(artist) }
function number(value) { return Math.max(0, Number(value) || 0) }

function addHistory(history, tracks, cutoff) {
  var result = Object.assign({}, history || {})
  var rows = list(tracks)
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i] || {}
    if (row["@attr"] && row["@attr"].nowplaying === "true") continue
    var artist = text(row.artist), title = text(row.name)
    var timestamp = number(row.date && row.date.uts)
    if (!artist || !title || timestamp < cutoff) continue
    var key = trackKey(artist, title)
    result[key] = Math.max(number(result[key]), timestamp)
  }
  Object.keys(result).forEach(function(key) {
    if (number(result[key]) < cutoff) delete result[key]
  })
  return result
}

function seeds(recent, monthly, lifetime, loved, feedback, maximum, rotation) {
  var map = {}
  function add(name, score) {
    name = text(name)
    if (!name) return
    var key = artistKey(name)
    if (!map[key]) map[key] = { name: name, weight: 0 }
    map[key].weight += score
  }
  function charts(rows, weight) {
    list(rows).slice(0, 20).forEach(function(row, index) {
      add(row.name, weight / Math.sqrt(index + 1))
    })
  }
  charts(recent, 0.6)
  charts(monthly, 0.3)
  charts(lifetime, 0.1)
  list(loved).slice(0, 100).forEach(function(row) { add(row.artist, 0.025) })
  Object.keys(feedback || {}).forEach(function(key) {
    var entry = feedback[key]
    if (entry && entry.rating === "more") add(entry.artist, 0.15)
  })
  var ordered = Object.keys(map).map(function(key) { return map[key] })
    .sort(function(a, b) { return b.weight - a.weight || a.name.localeCompare(b.name) })
  var count = maximum || 8, anchors = ordered.slice(0, 2), pool = ordered.slice(2)
  var start = pool.length ? number(rotation) % pool.length : 0
  return anchors.concat(pool.slice(start), pool.slice(0, start)).slice(0, count)
}

function mergeArtists(existing, rows, seed, secondDegree) {
  var map = {}
  list(existing).forEach(function(row) { map[artistKey(row.name)] = Object.assign({}, row) })
  list(rows).forEach(function(row) {
    var name = text(row.name), similarity = Math.min(1, number(row.match))
    if (!name || !similarity || nameKey(name) === nameKey(seed.name)) return
    var key = artistKey(name)
    var depth = secondDegree ? (seed.depth || 1) + 1 : 1
    var relevance = similarity * seed.weight * (secondDegree ? 0.65 : 1)
    if (!map[key]) map[key] = { name: name, relevance: 0, similarity: 0,
      seed: seed.origin || seed.name, secondDegree: !!secondDegree, depth: depth,
      path: (seed.path || [seed.name]).concat([name]), origins: [], monthlyListeners: null }
    map[key].relevance += relevance
    var origin = seed.origin || seed.name
    if (map[key].origins.indexOf(origin) < 0) map[key].origins = map[key].origins.concat([origin])
    if (depth < map[key].depth || (depth === map[key].depth && similarity > map[key].similarity)) {
      map[key].similarity = similarity
      map[key].seed = origin
      map[key].secondDegree = !!secondDegree
      map[key].depth = depth
      map[key].path = (seed.path || [seed.name]).concat([name])
    }
  })
  return Object.keys(map).map(function(key) { return map[key] })
}

function rankArtists(artists, obscurity, adventure, feedback) {
  var rows = list(artists).map(function(row) { return Object.assign({}, row) })
  var maxRelevance = Math.max.apply(Math, [0.001].concat(rows.map(function(row) { return row.relevance })))
  var adventurous = adventure === "Adventurous", close = adventure === "Close"
  return rows.filter(function(row) {
    return eligible(row.monthlyListeners, obscurity) && (!close || !row.secondDegree)
  }).map(function(row) {
    var similarityFit = adventurous ? 1 - Math.abs(row.similarity - 0.45) : row.similarity
    var depthFit = 1 - Math.log(1 + row.monthlyListeners) / Math.log(1 + listenerCeiling(obscurity))
    row.score = 0.5 * row.relevance / maxRelevance + 0.25 * similarityFit + 0.15 * depthFit
      + 0.1 * Math.min(1, list(row.origins).length / 3)
    if (row.familiar) row.score -= 0.2
    if (row.recentlyShown) row.score -= 0.35
    Object.keys(feedback || {}).forEach(function(key) {
      var entry = feedback[key]
      if (entry && entry.rating === "more" && nameKey(entry.artist) === nameKey(row.name)) row.score += 0.08
    })
    return row
  }).sort(function(a,b) { return b.score-a.score || a.name.localeCompare(b.name) })
}

function trackCandidates(artist, tracks, history, loved, feedback) {
  var lovedKeys = {}
  list(loved).forEach(function(row) { lovedKeys[trackKey(text(row.artist), row.name)] = true })
  return list(tracks).filter(function(row) {
    var key = trackKey(artist.name, row.name)
    return text(row.name) && !history[key] && !lovedKeys[key]
      && !(feedback[key] && feedback[key].rating === "less")
  }).map(function(row, index) {
    return { artist: artist.name, name: text(row.name), key: trackKey(artist.name, row.name),
      score: artist.score - index * 0.015, seed: artist.seed, monthlyListeners: artist.monthlyListeners,
      spotifyArtistId: artist.spotifyArtistId, listenerCheckedAt: artist.listenerCheckedAt,
      path: artist.path, secondDegree: artist.secondDegree }
  })
}

function rankedTracks(rows, shown, feedback, timestamp) {
  var seen = {}
  return list(rows).filter(function(row) {
    if (seen[row.key] || (feedback[row.key] && feedback[row.key].rating === "less")) return false
    seen[row.key] = true
    return true
  }).map(function(row) {
    var copy = Object.assign({}, row)
    if (shown[row.key] && timestamp-number(shown[row.key]) < 30*86400000) copy.score -= 0.6
    return copy
  }).sort(function(a,b) { return b.score-a.score || a.key.localeCompare(b.key) })
}

function spotifyMatch(candidate, tracks) {
  // Exact normalized title + artist prevents covers, same-name artists and
  // live/remastered substitutes. Different recordings with the same title
  // and artist are left unresolved if they have distinct known ISRCs.
  var matches = list(tracks).filter(function(track) {
    if (!track || track.type !== "track" || !track.id || !track.uri || track.is_playable === false
        || (track.restrictions && track.restrictions.reason)) return false
    if (nameKey(track.name) !== nameKey(candidate.name)) return false
    return list(track.artists).some(function(artist) {
      return nameKey(artist.name) === nameKey(candidate.artist)
        && (!candidate.spotifyArtistId || artist.id === candidate.spotifyArtistId)
    })
  })
  var recordings = {}
  matches.forEach(function(track) {
    var isrc = text(track.external_ids && track.external_ids.isrc)
    if (isrc) recordings[isrc] = true
  })
  return Object.keys(recordings).length > 1 ? null : matches[0] || null
}

function explanation(candidate) {
  var trail = list(candidate.path).slice(0, -1)
  var result = "Connected through " + (trail.length ? trail.join(" → ") : candidate.seed)
  if (validCount(candidate.monthlyListeners))
    result += " · " + candidate.monthlyListeners.toLocaleString() + " Spotify monthly listeners"
  else result += " · listener count unknown"
  return result
}

function validCount(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && Math.floor(value) === value && value <= 9007199254740991
}

function listenerCeiling(obscurity) {
  return obscurity === "Deep underground" ? 10000 : obscurity === "Underground" ? 50000 : 200000
}

function eligible(count, obscurity) { return validCount(count) && count < listenerCeiling(obscurity) }
function audienceBand(count) { return count < 10000 ? 0 : count < 50000 ? 1 : 2 }

function spotifyArtist(name, artists) {
  var found = {}, rows = list(artists).filter(function(row) {
    if (!row || row.type !== "artist" || !/^[A-Za-z0-9]{22}$/.test(row.id)
        || nameKey(row.name) !== nameKey(name) || found[row.id]) return false
    found[row.id] = true
    return true
  })
  return rows.length === 1 ? rows[0] : null
}

// Only exact counts from the artist's own labelled element qualify. Rounded
// SEO descriptions (e.g. 199.9K) cannot prove eligibility near a ceiling.
function parseAudience(html, artistId) {
  if (!/^[A-Za-z0-9]{22}$/.test(artistId) || typeof html !== "string" || html.length > 2000000) return null
  var canonical = html.match(/<link\b[^>]*rel=["']canonical["'][^>]*>/i)
  if (!canonical) return null
  var href = canonical[0].match(/href=["']([^"']+)["']/i)
  if (!href || href[1] !== "https://open.spotify.com/artist/" + artistId) return null
  var label = /<[^>]+\bdata-testid=["']monthly-listeners-label["'][^>]*>\s*([^<]+)</gi
  var match, count = null
  while ((match = label.exec(html))) {
    var exact = match[1].trim().match(/^((?:\d{1,3}(?:,\d{3})+)|\d+)\s+monthly listeners$/i)
    if (!exact) return null
    var value = Number(exact[1].replace(/,/g, ""))
    if (!validCount(value) || (count !== null && count !== value)) return null
    count = value
  }
  return count
}

// Give each listening seed a turn before spending the lookup budget. Smaller
// neighbours farther down a similarity list must get a chance to be checked.
function explorationOrder(artists, checked, seedNames, rotation) {
  var pools = {}, keys = list(seedNames).map(function(seed) { return artistKey(seed.name || seed) })
  var rows = list(artists).filter(function(row) { return !checked[artistKey(row.name)] })
    .sort(function(a,b) { return b.relevance-a.relevance || a.name.localeCompare(b.name) })
  rows.forEach(function(row) {
    var key = artistKey(row.seed)
    if (!pools[key]) { pools[key] = []; if (keys.indexOf(key) < 0) keys.push(key) }
    pools[key].push(row)
  })
  keys.forEach(function(key) {
    var pool = pools[key] || [], anchors = pool.slice(0, 2), rest = pool.slice(2)
    var start = rest.length ? number(rotation) % rest.length : 0
    pools[key] = anchors.concat(rest.slice(start), rest.slice(0, start))
  })
  var result = [], remaining = true
  while (remaining) {
    remaining = false
    keys.forEach(function(key) {
      if (pools[key] && pools[key].length) { result.push(pools[key].shift()); remaining = true }
    })
  }
  return result
}

// Targets are preferences, never a reason to admit an unknown/oversized artist.
// Backfill missing bands from other eligible picks, with one track per artist.
function selectFeed(rows, obscurity, maximum) {
  var target = obscurity === "Deep underground" ? [20,0,0]
    : obscurity === "Underground" ? [12,8,0] : [8,8,4]
  var sorted = list(rows).filter(function(row) { return eligible(row.discoveryMonthlyListeners,obscurity) })
    .sort(function(a,b) { return b.discoveryScore-a.discoveryScore || a.discoveryKey.localeCompare(b.discoveryKey) })
  var result = [], used = {}, counts = [0,0,0], max = maximum || 20
  function add(row, enforceTarget) {
    var id = row.discoverySpotifyArtistId, band = audienceBand(row.discoveryMonthlyListeners)
    if (!id || used[id] || result.length >= max || (enforceTarget && counts[band] >= target[band])) return
    used[id] = true; counts[band]++; result.push(row)
  }
  sorted.forEach(function(row) { add(row,true) })
  sorted.forEach(function(row) { add(row,false) })
  return result.sort(function(a,b) { return b.discoveryScore-a.discoveryScore || a.discoveryKey.localeCompare(b.discoveryKey) })
}

function boundedMap(source, maximum) {
  var keys = Object.keys(source || {}).sort(function(a,b) {
    var left = source[a], right = source[b]
    return number(right && typeof right === "object" ? right.at : right)
      - number(left && typeof left === "object" ? left.at : left)
  }).slice(0, maximum)
  var result = {}
  keys.forEach(function(key) { result[key] = source[key] })
  return result
}

function settingsFingerprint(obscurity, adventure) { return "spotify-audience-v2|" + String(obscurity) + "|" + String(adventure) }
