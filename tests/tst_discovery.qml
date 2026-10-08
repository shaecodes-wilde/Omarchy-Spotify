import QtQuick
import QtTest
import "../Discovery.js" as Discovery
import "../Api.js" as Api

TestCase {
  name: "DiscoveryRanking"

  function test_history_ignoresNowPlayingAndExpiresOldEntries() {
    var heard = Discovery.trackKey("A", "Song")
    var history = Discovery.addHistory({ "$old": 20 }, [
      { artist: { "#text": "A" }, name: "Song", date: { uts: "120" } },
      { artist: "B", name: "Playing", "@attr": { nowplaying: "true" }, date: { uts: "130" } }
    ],100)
    compare(history[heard],120)
    compare(Object.keys(history).length,1)
  }

  function test_ranking_treatsMissingListenersAsUnknown() {
    var artists = [
      { name: "Known small", relevance: 1, similarity: 0.8, lastFmListeners: 100 },
      { name: "Big", relevance: 1, similarity: 0.8, lastFmListeners: 1000000 },
      { name: "Unknown", relevance: 1, similarity: 0.8, lastFmListeners: null }
    ]
    var result = Discovery.rankArtists(artists,"Deep underground","Balanced",{})
    compare(result[0].name,"Known small")
    compare(result.length,1)
    compare(artists[0].score,undefined)
  }

  function test_closeAdventure_excludesSecondDegree() {
    compare(Discovery.rankArtists([
      { name: "Direct", relevance: 1, similarity: 0.9, lastFmListeners: 100 },
      { name: "Distant", relevance: 1, similarity: 0.8, lastFmListeners: 20, secondDegree: true }
    ],"Underground","Close",{}).length,1)
  }

  function test_tracks_excludeHistoryLovedAndNegativeFeedback() {
    var artist = { name: "A", score: 1, seed: "Seed", lastFmListeners: 20 }
    var history = {}, feedback = {}
    history[Discovery.trackKey("A","Heard")] = 100
    feedback[Discovery.trackKey("A","Hidden")] = { rating: "less" }
    var result = Discovery.trackCandidates(artist,[
      { name: "Heard" }, { name: "Loved" }, { name: "Hidden" }, { name: "New" }
    ],history,[{ name: "Loved", artist: { name: "A" } }],feedback)
    compare(result.length,1)
    compare(result[0].name,"New")
  }

  function test_matching_rejectsCoversVariantsAndAmbiguousRecordings() {
    var candidate = { artist: "A", name: "Song" }
    function track(artist,title,isrc) {
      return { type: "track", id: "id", uri: "spotify:track:id", name: title,
        artists: [{ name: artist }], external_ids: { isrc: isrc } }
    }
    compare(Discovery.spotifyMatch(candidate,[track("Cover band","Song","one")]),null)
    compare(Discovery.spotifyMatch(candidate,[track("A","Song - Live","one")]),null)
    compare(Discovery.spotifyMatch(candidate,[track("A","Song","one"),track("A","Song","two")]),null)
    verify(Discovery.spotifyMatch(candidate,[track("a","song","one")]))
    var blocked = track("A","Song","one"); blocked.is_playable = false
    compare(Discovery.spotifyMatch(candidate,[blocked]),null)
  }

  function test_repeatedSuggestions_arePenalizedWithoutRandomizingCache() {
    var rows = [{ key: "a", score: 1 }, { key: "b", score: 0.9 }]
    var shown = { a: 10000 }
    compare(Discovery.rankedTracks(rows,shown,{},10001)[0].key,"b")
    compare(Discovery.rankedTracks(rows,shown,{},10001)[0].key,"b")
  }

  function test_feedback_influencesSeedsAndKeysCannotPollutePrototypes() {
    var feedback = { "$x": { artist: "Favorite", rating: "more" } }
    compare(Discovery.seeds([],[],[],[],feedback,6)[0].name,"Favorite")
    verify(Discovery.artistKey("__proto__").charAt(0) === "$")
  }

  function test_keysAndExplanation_neverConfuseListenerMetrics() {
    compare(Discovery.trackKey(" A ","Song"),Discovery.trackKey("a"," SONG "))
    verify(Discovery.explanation({ seed: "A", lastFmListeners: null }).indexOf("unknown") >= 0)
    verify(Discovery.explanation({ seed: "A", lastFmListeners: 100 }).indexOf("Last.fm total listeners") >= 0)
    compare(Api.searchScope("home",null,null,"gems","").label,"Hidden gems")
    verify(Api.redact("api_key=abc lastFmApiKey=def").indexOf("abc") < 0)
  }

  function test_strictCeilings() {
    ;["Obscure","Underground","Deep underground"].forEach(function(mode) {
      var ceiling = Discovery.listenerCeiling(mode)
      verify(Discovery.eligible(ceiling-1,mode))
      verify(!Discovery.eligible(ceiling,mode))
      verify(!Discovery.eligible(ceiling+1,mode))
      ;[null,undefined,"100",NaN,Infinity,-1,1.1].forEach(function(count) {
        verify(!Discovery.eligible(count,mode))
      })
      verify(Discovery.eligible(0,mode))
    })
  }

  function test_lastFmTotalCountsRequireExactProfileAndNumbers() {
    function payload(value,name) { return {artist:{name:name || "Small",stats:{listeners:value}}} }
    compare(Discovery.lastFmListenerCount(payload("199999"),"small"),199999)
    compare(Discovery.lastFmListenerCount(payload("200000"),"Small"),200000)
    compare(Discovery.lastFmListenerCount(payload("0"),"Small"),0)
    compare(Discovery.lastFmListenerCount(payload(123),"Small"),123)
    compare(Discovery.lastFmListenerCount(payload("100","Other"),"Small"),null)
    ;[null,undefined,"","199.9K","1,000","1e3","-1","1.2",false,Infinity,NaN].forEach(function(value) {
      compare(Discovery.lastFmListenerCount(payload(value),"Small"),null)
    })
    compare(Discovery.lastFmListenerCount({artist:{name:"Small",stats:{playcount:"100"}}},"Small"),null)
    compare(Discovery.lastFmListenerCount(null,"Small"),null)
    verify(Discovery.explanation({seed:"A",lastFmListeners:100}).indexOf("monthly")<0)
  }

  function test_artistIdentityRejectsSameNameAmbiguity() {
    var a = { type: "artist", id: "abcdefghijklmnopqrstuv", name: "Small" }
    var b = { type: "artist", id: "ABCDEFGHIJKLMNOPQRSTUV", name: "Small" }
    compare(Discovery.spotifyArtist("small",[a]).id,a.id)
    compare(Discovery.spotifyArtist("small",[a,b]),null)
    compare(Discovery.spotifyArtist("small",[{ type:"artist",id:"invalid",name:"Small" }]),null)
  }

  function test_smallArtistFeedMixAndNoCeilingBackfill() {
    var rows = []
    for (var band=0; band<3; band++) for (var i=0; i<12; i++) {
      rows.push({ discoveryKey: band+"-"+i, discoverySpotifyArtistId: band+"-"+i,
        discoveryLastFmListeners: [1000,20000,100000][band], discoveryScore: [0.3,0.5,0.9][band] })
    }
    rows.push({ discoveryKey:"huge", discoverySpotifyArtistId:"huge", discoveryLastFmListeners:200000,discoveryScore:100 })
    rows.push(Object.assign({},rows[0],{ discoveryKey:"duplicate",discoveryScore:0.1 }))
    var feed = Discovery.selectFeed(rows,"Obscure",20), counts=[0,0,0]
    feed.forEach(function(row) { counts[Discovery.audienceBand(row.discoveryLastFmListeners)]++ })
    compare(feed.length,20); compare(counts.join(","),"8,8,4")
    compare(Discovery.selectFeed(rows,"Deep underground",20).length,12)
    verify(Discovery.selectFeed(rows,"Underground",20).every(function(row) { return row.discoveryLastFmListeners < 50000 }))
  }

  function test_searchBudgetGivesEachSeedATurnAndRotates() {
    var rows = []
    for (var i=0;i<12;i++) rows.push({ name:"A"+i, seed:"A", relevance:100-i })
    for (var j=0;j<12;j++) rows.push({ name:"B"+j, seed:"B", relevance:10-j })
    var ranked = Discovery.explorationOrder(rows,{},["A","B"],0)
    compare(ranked.slice(0,4).map(function(row) { return row.seed }).join(","),"A,B,A,B")
    var rotated = Discovery.explorationOrder(rows,{},["A","B"],3)
    verify(rotated[4].name !== ranked[4].name)
    var checked = {}; checked[Discovery.artistKey("A0")] = true
    verify(!Discovery.explorationOrder(rows,checked,["A","B"],0).some(function(row) { return row.name === "A0" }))
  }

  function test_deeperGraphPreservesDirectConnections() {
    var rows = Discovery.mergeArtists([],[{name:"Small",match:0.4}],{name:"Seed",weight:1},false)
    rows = Discovery.mergeArtists(rows,[{name:"Small",match:0.9}],
      {name:"Neighbour",origin:"Seed",weight:0.5,depth:2,path:["Seed","Neighbour"]},true)
    compare(rows[0].depth,1)
    compare(rows[0].secondDegree,false)
    compare(rows[0].path.join(" → "),"Seed → Small")
  }
}
