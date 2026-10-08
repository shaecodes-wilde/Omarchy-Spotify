import QtQuick
import Quickshell.Io
import "Api.js" as Api
import "Discovery.js" as Discovery

Item {
  id: root
  visible: false
  required property var host
  property var now: function() { return Date.now() }
  readonly property string username: String(host.settings.lastFmUsername || "").trim()
  readonly property string apiKey: String(host.settings.lastFmApiKey || "").trim()
  readonly property string obscurity: String(host.settings.discoveryObscurity || "Obscure")
  readonly property string adventure: String(host.settings.discoveryAdventure || "Balanced")
  readonly property string fingerprint: Discovery.settingsFingerprint(obscurity, adventure)
  readonly property string scope: host.accountConnected && host.currentUserId && username
    ? username.toLowerCase() + "|" + host.currentUserId : ""
  readonly property string storageDirectory: host.stateDir + "/discovery"
  readonly property string storagePath: scope && directoryReady && storageEnabled
    ? storageDirectory + "/" + encodeURIComponent(scope) + ".json" : ""
  property bool storageEnabled: true
  property bool directoryReady: false
  property bool storeReady: false
  property bool requested: false
  property bool forceRequested: false
  property bool loading: false
  property int generation: 0
  property var items: []
  property string message: ""
  property string warning: ""
  property double loadedAt: 0
  property string loadedFingerprint: ""
  property double failedAt: 0
  property var history: ({})
  property var feedback: ({})
  property var shown: ({})
  property var matches: ({})
  property var spotifyHandle: null
  property int importedCount: 0
  property bool historyLimited: false
  property var recentChart: []
  property var monthlyChart: []
  property var lifetimeChart: []
  property var loved: []
  property var seedArtists: []
  property var candidateArtists: []
  property var candidates: []
  property var resolved: []
  property var artistCounts: ({})
  property var shownArtists: ({})
  property int seedRotation: 0
  property var checkedArtists: ({})
  property var verificationQueue: []
  property var expansionParents: []
  property var verifiedArtists: []
  property var familiarArtists: ({})
  property int verificationCount: 0
  property int unknownCounts: 0
  property int artistLookupCount: 0
  property int trackLookupCount: 0
  readonly property int artistBudget: 120
  readonly property string obscurityLabel: obscurity + " · <" + Discovery.listenerCeiling(obscurity).toLocaleString()
  readonly property string setupMessage: !username ? "Add your Last.fm username in Settings."
    : !/^[0-9a-f]{32}$/i.test(apiKey) ? "Add a Last.fm API key in Settings to find hidden gems."
    : !host.accountConnected ? "Connect Spotify to play your discoveries."
    : !host.currentUserId ? "Checking your Spotify profile. Try Refresh if this takes too long." : ""

  LastFmApi { id: lastFm; apiKey: root.apiKey; now: root.now }
  readonly property alias provider: lastFm
  SpotifyAudience { id: audience; now: root.now }
  readonly property alias audienceProvider: audience

  onScopeChanged: reset(true)
  onApiKeyChanged: {
    cancel()
    failedAt = 0
    if (requested) ensure(false)
  }
  onFingerprintChanged: {
    cancel()
    items = []
    loadedAt = 0
    failedAt = 0
    if (requested) ensure(true)
  }

  function cancel() {
    generation++
    loading = false
    lastFm.cancelAll()
    audience.cancelAll()
    if (spotifyHandle) host.api.abortRequest(spotifyHandle)
    spotifyHandle = null
  }

  function reset(reload) {
    saveTimer.stop()
    cancel()
    storeReady = false
    items = []
    history = ({})
    feedback = ({})
    shown = ({})
    matches = ({})
    audience.cache = ({})
    shownArtists = ({})
    seedRotation = 0
    loadedAt = 0
    failedAt = 0
    importedCount = 0
    historyLimited = false
    warning = ""
    message = ""
    loadedFingerprint = ""
    clearWorkingData()
    forceRequested = false
    if (!scope) { requested = false; return }
  }

  function clearWorkingData() {
    recentChart = []; monthlyChart = []; lifetimeChart = []; loved = []
    seedArtists = []; candidateArtists = []; candidates = []; resolved = []
    artistCounts = ({})
    checkedArtists = ({}); verificationQueue = []; expansionParents = []; verifiedArtists = []
    familiarArtists = ({}); verificationCount = 0; unknownCounts = 0
    artistLookupCount = 0; trackLookupCount = 0
  }

  function readState(raw) {
    if (!scope || storeReady) return
    var record = null
    try { record = JSON.parse(raw) } catch (error) {}
    if (record && [1,2].indexOf(record.version) >= 0 && record.scope === scope) {
      history = Discovery.boundedMap(record.history, 5000)
      feedback = Discovery.boundedMap(record.feedback, 2000)
      shown = Discovery.boundedMap(record.shown, 1000)
      matches = Discovery.boundedMap(record.matches, 200)
      loadedAt = Discovery.number(record.loadedAt)
      loadedFingerprint = String(record.fingerprint || "")
      audience.cache = Discovery.boundedMap(record.audience,400)
      shownArtists = Discovery.boundedMap(record.shownArtists,1000)
      seedRotation = Discovery.number(record.seedRotation)
      items = loadedFingerprint === fingerprint ? Discovery.list(record.items).filter(function(item) {
        return root.validStoredItem(item)
      }).slice(0,20) : []
      if (loadedFingerprint !== fingerprint || items.length !== Discovery.list(record.items).length) loadedAt = 0
      importedCount = Discovery.number(record.importedCount)
      historyLimited = record.historyLimited === true
      warning = String(record.warning || "")
    }
    storeReady = true
    if (requested) ensure(forceRequested)
  }

  function save() {
    if (storeReady && scope && directoryReady) saveTimer.restart()
  }

  function writeState() {
    if (!storeReady || !scope || !directoryReady) return
    stateFile.setText(JSON.stringify({ version: 2, scope: scope, items: items,
      history: Discovery.boundedMap(history,5000), feedback: Discovery.boundedMap(feedback,2000),
      shown: Discovery.boundedMap(shown,1000), matches: Discovery.boundedMap(matches,200),
      audience: Discovery.boundedMap(audience.cache,400), shownArtists: Discovery.boundedMap(shownArtists,1000),
      seedRotation: seedRotation, loadedAt: loadedAt, fingerprint: loadedFingerprint,
      importedCount: importedCount, historyLimited: historyLimited, warning: warning }))
  }

  function ensure(force) {
    requested = true
    forceRequested = forceRequested || !!force
    if (setupMessage) { message = setupMessage; return }
    if (!storeReady || loading) return
    items = items.filter(function(item) { return root.validStoredItem(item) })
    if (!forceRequested && loadedAt && now()-loadedAt < 86400000 && loadedFingerprint === fingerprint && items.length) {
      message = items.length ? "" : "No new matches today. Try more adventure or Refresh."
      return
    }
    if (!forceRequested && failedAt && now()-failedAt < 60000) return
    forceRequested = false
    failedAt = 0
    loading = true
    message = "Reading your Last.fm listening history…"
    warning = ""
    importedCount = 0
    historyLimited = false
    clearWorkingData()
    var token = ++generation
    readHistory(1, Math.floor(now()/1000)-90*86400, token)
  }

  function fail(reason, token) {
    if (token !== generation) return
    cancel()
    failedAt = now()
    message = String(reason || "Discovery could not finish. Try Refresh later.")
    save()
  }

  function request(method, params, token, callback, freshness) {
    lastFm.request(method, params, function(payload, error) {
      if (!root || token !== root.generation) return
      callback(payload, error)
    }, freshness)
  }

  function readHistory(page, cutoff, token) {
    request("user.getRecentTracks", { user: username, limit: 200, page: page, from: cutoff }, token,
      function(payload, error) {
        if (error) { root.fail(error,token); return }
        var container = payload.recenttracks || {}
        var rows = Discovery.list(container.track)
        root.history = Discovery.addHistory(root.history,rows,cutoff)
        root.importedCount += rows.filter(function(row) { return !(row["@attr"] && row["@attr"].nowplaying === "true") }).length
        var pages = Discovery.number(container["@attr"] && container["@attr"].totalPages)
        if (page < pages && page < 25 && rows.length) root.readHistory(page+1,cutoff,token)
        else {
          root.historyLimited = page < pages
          root.readCharts(0,token)
        }
      }, 0)
  }

  function readCharts(index, token) {
    var periods = ["7day","1month","overall"]
    if (index === periods.length) { readLoved(token); return }
    request("user.getTopArtists", { user: username, period: periods[index], limit: 20 },token,
      function(payload,error) {
        if (error) { root.fail(error,token); return }
        var rows = Discovery.list(payload.topartists && payload.topartists.artist)
        if (index === 0) root.recentChart = rows
        else if (index === 1) root.monthlyChart = rows
        else root.lifetimeChart = rows
        root.readCharts(index+1,token)
      }, 3600000)
  }

  function readLoved(token) {
    request("user.getLovedTracks",{ user: username, limit: 100 },token,function(payload,error) {
      if (error) { root.fail(error,token); return }
      root.loved = Discovery.list(payload.lovedtracks && payload.lovedtracks.track)
      root.seedArtists = Discovery.seeds(root.recentChart,root.monthlyChart,root.lifetimeChart,root.loved,root.feedback,8,root.seedRotation)
      var familiar = {}
      Object.keys(root.history).forEach(function(key) { familiar[key.split("\u001f")[0]] = true })
      root.recentChart.concat(root.monthlyChart,root.lifetimeChart).forEach(function(row) { familiar[Discovery.artistKey(row.name)] = true })
      root.loved.forEach(function(row) { familiar[Discovery.artistKey(Discovery.text(row.artist))] = true })
      root.familiarArtists = familiar
      if (!root.seedArtists.length) { root.fail("Last.fm has no listening favorites yet. Keep scrobbling and try again.",token); return }
      root.message = "Finding artists connected to your favorites…"
      root.readSimilar(0,token)
    },3600000)
  }

  function readSimilar(index,token) {
    if (index >= seedArtists.length) {
      var ordered = Discovery.explorationOrder(candidateArtists,{},seedArtists,seedRotation)
      expansionParents = []
      var branches = Math.min(adventure === "Adventurous" ? 8 : 6,ordered.length)
      for (var i=0; i<branches; i++) expansionParents.push(ordered[Math.floor(i*ordered.length/branches)])
      readSecondDegree(0,token); return
    }
    var seed = seedArtists[index]
    request("artist.getSimilar", { artist: seed.name, limit: 30, autocorrect: 1 },token,function(payload,error) {
      if (error) { root.fail(error,token); return }
      root.candidateArtists = Discovery.mergeArtists(root.candidateArtists,
        payload.similarartists && payload.similarartists.artist,seed,false)
      root.readSimilar(index+1,token)
    })
  }

  function readSecondDegree(index,token) {
    if (adventure === "Close" || index >= expansionParents.length) {
      beginVerification(80,token,false)
      return
    }
    var parent = expansionParents[index]
    request("artist.getSimilar",{ artist: parent.name, limit: 24, autocorrect: 1 },token,function(payload,error) {
      if (error) { root.fail(error,token); return }
      root.candidateArtists = Discovery.mergeArtists(root.candidateArtists,
        payload.similarartists && payload.similarartists.artist,
        { name: parent.name, origin: parent.seed, weight: parent.relevance,
          depth: parent.depth, path: parent.path },true)
      root.readSecondDegree(index+1,token)
    })
  }

  function beginVerification(limit,token,finalPass) {
    var seeds = {}
    seedArtists.forEach(function(row) { seeds[Discovery.artistKey(row.name)] = true })
    var pool = candidateArtists.filter(function(row) { return !seeds[Discovery.artistKey(row.name)] })
    verificationQueue = Discovery.explorationOrder(pool,checkedArtists,seedArtists,seedRotation)
      .slice(0,Math.min(limit,artistBudget-verificationCount))
    message = "Checking Spotify monthly listeners · " + verificationCount + "/" + artistBudget + "…"
    verifyArtist(0,token,finalPass)
  }

  function verifyArtist(index,token,finalPass) {
    if (index >= verificationQueue.length) {
      if (!finalPass && adventure !== "Close") {
        // Walk outward from artists whose small audience has actually been
        // verified, instead of repeatedly expanding the biggest neighbours.
        expansionParents = Discovery.rankArtists(verifiedArtists,obscurity,adventure,feedback).slice(0,6)
        readDeepNeighbours(0,token)
      } else if (!finalPass) beginVerification(40,token,true)
      else prepareTracks(token)
      return
    }
    var artist = verificationQueue[index]
    checkedArtists[Discovery.artistKey(artist.name)] = true
    verificationCount++
    message = "Checking Spotify monthly listeners · " + verificationCount + "/" + artistBudget + "…"
    var quote = String(artist.name).replace(/["\\]/g," ")
    artistLookupCount++
    spotifyHandle = host.api.request("GET","/search",{ q: 'artist:"'+quote+'"', type: "artist", limit: 10 },null,
      function(status,payload,error) {
        if (!root || token !== root.generation) return
        root.spotifyHandle = null
        if (error) { root.fail("Spotify could not search discovery artists. Try Refresh later.",token); return }
        var match = Discovery.spotifyArtist(artist.name,payload && payload.artists && payload.artists.items)
        if (!match) { root.unknownCounts++; root.verifyArtist(index+1,token,finalPass); return }
        audience.request(match.id,function(record,audienceError,reason) {
          if (!root || token !== root.generation) return
          if (audienceError) { root.fail(audienceError,token); return }
          if (record && Discovery.eligible(record.listeners,root.obscurity)) {
            var copy = Object.assign({},artist,{ spotifyArtistId: match.id, monthlyListeners: record.listeners,
              listenerCheckedAt: record.at, familiar: !!root.familiarArtists[Discovery.artistKey(artist.name)],
              recentlyShown: !!root.shownArtists[match.id] && root.now()-root.shownArtists[match.id] < 30*86400000 })
            if (!root.verifiedArtists.some(function(row) { return row.spotifyArtistId === match.id }))
              root.verifiedArtists = root.verifiedArtists.concat([copy])
          } else if (!record) root.unknownCounts++
          root.verifyArtist(index+1,token,finalPass)
        })
      },{ priority: "background", retryRateLimit: false })
  }

  function readDeepNeighbours(index,token) {
    if (index >= expansionParents.length) { beginVerification(40,token,true); return }
    var parent = expansionParents[index]
    request("artist.getSimilar",{ artist: parent.name, limit: 24, autocorrect: 1 },token,function(payload,error) {
      if (error) { root.fail(error,token); return }
      root.candidateArtists = Discovery.mergeArtists(root.candidateArtists,
        payload.similarartists && payload.similarartists.artist,
        { name: parent.name, origin: parent.seed, weight: parent.relevance,
          depth: parent.depth, path: parent.path },true)
      root.readDeepNeighbours(index+1,token)
    })
  }

  function prepareTracks(token) {
    var ranked = Discovery.rankArtists(verifiedArtists,obscurity,adventure,feedback)
    // Reserve space for each audience band before filling remaining slots.
    var selected = [], used = {}, bands = [0,0,0]
    ranked.forEach(function(row) {
      var band = Discovery.audienceBand(row.monthlyListeners)
      if (bands[band] < 12) { selected.push(row); used[row.spotifyArtistId] = true; bands[band]++ }
    })
    ranked.forEach(function(row) {
      if (!used[row.spotifyArtistId] && selected.length < 40) selected.push(row)
    })
    candidateArtists = selected.slice(0,40)
    message = "Finding introductions to verified small artists…"
    readArtistTracks(0,token)
  }

  function readArtistTracks(index,token) {
    if (index >= candidateArtists.length) {
      candidates = Discovery.rankedTracks(candidates,shown,feedback,now())
      message = "Matching discoveries to Spotify…"
      resolveTrack(0,token)
      return
    }
    var artist = candidateArtists[index]
    request("artist.getTopTracks", { artist: artist.name, limit: 5, autocorrect: 1 },token,function(payload,error) {
      if (error && error !== "Last.fm could not find that profile or artist.") { root.fail(error,token); return }
      if (!error) root.candidates = root.candidates.concat(Discovery.trackCandidates(artist,
        payload.toptracks && payload.toptracks.track,root.history,root.loved,root.feedback))
      root.readArtistTracks(index+1,token)
    })
  }

  function resolveTrack(index,token) {
    if (index >= candidates.length || trackLookupCount >= 100) { finish(token); return }
    var candidate = candidates[index], key = Discovery.artistKey(candidate.artist)
    if ((artistCounts[key] || 0) >= 1) { resolveTrack(index+1,token); return }
    var cached = matches[candidate.key]
    if (cached && now()-cached.at < (cached.item ? 30 : 7)*86400000) {
      checkTrackAudience(candidate,cached.item,token,function() { root.resolveTrack(index+1,token) })
      return
    }
    var quote = function(value) { return String(value).replace(/["\\]/g," ") }
    trackLookupCount++
    spotifyHandle = host.api.request("GET","/search",{
      q: 'track:"'+quote(candidate.name)+'" artist:"'+quote(candidate.artist)+'"', type: "track", limit: 10
    },null,function(status,payload,error) {
      if (!root || token !== root.generation) return
      root.spotifyHandle = null
      if (error) { root.fail("Spotify could not match discoveries. Try Refresh after its request limit clears.",token); return }
      var raw = Discovery.spotifyMatch(candidate,payload && payload.tracks && payload.tracks.items)
      var item = raw ? Api.normalizeTrack(raw,96) : null
      var next = Object.assign({},root.matches)
      next[candidate.key] = { at: root.now(), item: item }
      root.matches = Discovery.boundedMap(next,200)
      root.checkTrackAudience(candidate,item,token,function() { root.resolveTrack(index+1,token) })
    },{ priority: "background", retryRateLimit: false })
  }

  function validStoredItem(item) {
    if (!item || item.type !== "track" || !item.uri || !item.discoverySpotifyArtistId
        || !Discovery.eligible(item.discoveryMonthlyListeners,obscurity)
        || !item.artists || !item.artists.length) return false
    if (!item.artists.some(function(artist) { return artist.id === item.discoverySpotifyArtistId })) return false
    return item.artists.every(function(artist) {
      var record = audience.cache[artist.id]
      return audience.fresh(record,artist.id) && Discovery.eligible(record.listeners,root.obscurity)
        && (artist.id !== item.discoverySpotifyArtistId || record.listeners === item.discoveryMonthlyListeners)
    })
  }

  function checkTrackAudience(candidate,item,token,done) {
    if (!item || !item.artists || !item.artists.length || !item.artists.some(function(artist) {
      return artist.id === candidate.spotifyArtistId
    })) { done(); return }
    // A huge featured artist must not sneak into a supposedly obscure feed.
    function next(index) {
      if (!root || token !== root.generation) return
      if (index >= item.artists.length) { root.accept(candidate,item); done(); return }
      var id = item.artists[index].id
      if (!audience.fresh(audience.cache[id],id)) {
        if (root.verificationCount >= root.artistBudget) { done(); return }
        root.verificationCount++
      }
      audience.request(id,function(record,error,reason) {
        if (!root || token !== root.generation) return
        if (error) { root.fail(error,token); return }
        if (!record || !Discovery.eligible(record.listeners,root.obscurity)) { done(); return }
        next(index+1)
      })
    }
    next(0)
  }

  function accept(candidate,item) {
    if (!item || resolved.some(function(row) { return row.uri === item.uri })) return
    var copy = Object.assign({},item,{ discoveryKey: candidate.key,
      discoveryArtist: candidate.artist, discoveryReason: Discovery.explanation(candidate),
      discoverySeed: candidate.seed, discoveryMonthlyListeners: candidate.monthlyListeners,
      discoverySpotifyArtistId: candidate.spotifyArtistId, discoveryListenerCheckedAt: candidate.listenerCheckedAt,
      discoveryScore: candidate.score })
    resolved = resolved.concat([copy])
    artistCounts[Discovery.artistKey(candidate.artist)] = (artistCounts[Discovery.artistKey(candidate.artist)] || 0)+1
  }

  function finish(token) {
    if (token !== generation) return
    items = Discovery.selectFeed(resolved.filter(function(item) { return root.validStoredItem(item) }),obscurity,20)
    loadedAt = now()
    loadedFingerprint = fingerprint
    loading = false
    var next = Object.assign({},shown)
    var nextArtists = Object.assign({},shownArtists)
    items.forEach(function(item) { next[item.discoveryKey] = root.now(); nextArtists[item.discoverySpotifyArtistId] = root.now() })
    shown = Discovery.boundedMap(next,1000)
    shownArtists = Discovery.boundedMap(nextArtists,1000)
    seedRotation = (seedRotation + 6) % 1000000
    message = items.length ? "" : "No verified matches below " + Discovery.listenerCeiling(obscurity).toLocaleString()
      + " Spotify monthly listeners. Try more adventure or Refresh."
    warning = historyLimited ? "Filtered against the latest 5,000 scrobbles within 90 days; older plays may reappear."
      : "Filtered against your imported 90-day history and up to 100 loved tracks."
    warning = "Spotify monthly listeners checked within 24 hours · " + verificationCount + " artists checked. " + warning
    if (unknownCounts) warning += " " + unknownCounts + " artists skipped because identity or count could not be verified."
    save()
  }

  function rate(item,rating) {
    if (!item || !item.discoveryKey || ["more","less"].indexOf(rating) < 0) return
    var next = Object.assign({},feedback)
    next[item.discoveryKey] = { artist: item.discoveryArtist, rating: rating, at: now() }
    feedback = Discovery.boundedMap(next,2000)
    if (rating === "less") items = items.filter(function(row) { return row.discoveryKey !== item.discoveryKey })
    save()
  }

  function clearHistory() {
    cancel()
    history = ({}); feedback = ({}); shown = ({}); matches = ({})
    audience.cache = ({}); shownArtists = ({}); seedRotation = 0
    clearWorkingData()
    items = []; loadedAt = 0; failedAt = 0; importedCount = 0; historyLimited = false
    warning = ""
    lastFm.cache = ({})
    message = "Local discovery history cleared. Refresh to import it again."
    save()
  }

  Timer { id: saveTimer; interval: 200; onTriggered: root.writeState() }
  FileView {
    id: stateFile
    path: root.storagePath
    atomicWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.readState(text())
    onLoadFailed: root.readState("")
    onSaveFailed: root.message = "Discoveries are available, but their local cache could not be saved."
  }
  Process {
    id: ensureDirectory
    command: ["/usr/bin/mkdir","-p","-m","700",root.storageDirectory]
    running: root.storageEnabled
    onExited: function(exitCode) {
      root.directoryReady = exitCode === 0
      if (!root.directoryReady) {
        root.storeReady = true
        root.message = "The discovery cache directory could not be created."
      }
    }
  }
  Component.onDestruction: {
    if (saveTimer.running) writeState()
    cancel()
  }
}
