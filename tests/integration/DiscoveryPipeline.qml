import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/Discovery.js" as Discovery

ShellRoot {
  id: tests
  property int spotifySearches: 0
  property int lastFmCalls: 0
  property bool holdResponse: false
  property var held: null
  property var controller: null
  property double clock: 1800000000000
  property int audienceCalls: 0
  property bool holdAudience: false
  property var heldAudience: null
  property int phase: 0
  property var counts: ({ "Artist A":100, "Artist B":49999, "Ceiling":200000,
    "Boundary":50000, "Tiny boundary":10000, "Zero":0, "Unknown":null, "Collab":500, "Deep find":300 })
  function artistId(name) { return (name.replace(/\s/g,"")+"0000000000000000000000").slice(0,22) }
  QtObject {
    id: fakeHost
    property var settings: ({ lastFmUsername: "profile", lastFmApiKey: "0123456789abcdef0123456789abcdef",
      discoveryObscurity: "Obscure", discoveryAdventure: "Balanced" })
    property bool accountConnected: true
    property string currentUserId: "spotify-account"
    property string stateDir: "/tmp/omarchy-discovery-unit-tests"
    property var api: spotify
  }
  QtObject {
    id: spotify
    function request(method,path,query,body,callback,options) {
      tests.spotifySearches++
      if (query.type === "artist") {
        var name=query.q.match(/artist:"([^"]+)"/)[1]
        var artistHandle={aborted:false}
        Qt.callLater(function() {
          if (!artistHandle.aborted) callback(200,{artists:{items:[{type:"artist",id:tests.artistId(name),name:name}]}},"")
        })
        return artistHandle
      }
      var match = query.q.match(/track:"([^"]+)" artist:"([^"]+)"/)
      var handle = { aborted: false }
      Qt.callLater(function() {
        if (handle.aborted) return
        var artists=[{ name:match[2], id:tests.artistId(match[2]) }]
        if (match[2] === "Collab" && match[1] !== "New three") artists.push({name:"Ceiling",id:tests.artistId("Ceiling")})
        callback(200,{ tracks: { items: [{ type: "track", id: match[1]+match[2],
          uri: "spotify:track:"+match[1]+match[2], name: match[1], artists: artists }] } },"")
      })
      return handle
    }
    function abortRequest(handle) { handle.aborted = true }
  }
  Component {
    id: component
    Plugin.DiscoveryController {
      host: fakeHost
      storageEnabled: false
      now: function() { return tests.clock }
    }
  }

  function response(url) {
    var query = {}
    url.split("?")[1].split("&").forEach(function(pair) {
      var values = pair.split("="); query[values[0]] = decodeURIComponent(values[1])
    })
    if (query.method === "user.getRecentTracks") return { recenttracks: {
      track: [{ artist: { "#text": "Artist A" }, name: "Heard", date: { uts: String(Math.floor(clock/1000)-100) } }],
      "@attr": { totalPages: "1" } } }
    if (query.method === "user.getTopArtists") return { topartists: { artist: [{ name: "Seed", playcount: "30" }] } }
    if (query.method === "user.getLovedTracks") return { lovedtracks: { track: [{ name: "Loved", artist: { name: "Artist A" } }] } }
    if (query.method === "artist.getSimilar") return { similarartists: { artist: query.artist === "Seed"
      ? Object.keys(counts).filter(function(name) { return name !== "Deep find" }).map(function(name) { return {name:name,match:"0.8"} })
      : query.artist === "Zero" ? [{name:"Deep find",match:"0.7"}] : [] } }
    if (query.method === "artist.getInfo") throw new Error("Last.fm audience must not substitute for Spotify monthly listeners")
    if (query.method === "artist.getTopTracks") return { toptracks: { track: [
      { name: "Heard" }, { name: "Loved" }, { name: "New one" }, { name: "New two" }, { name: "New three" } ] } }
    return { error: 6 }
  }
  function newRequest() {
    var xhr = { readyState: 0, status: 0, responseText: "", url: "", aborted: false,
      open: function(method,url) { this.url=url },
      abort: function() { this.aborted=true }, getResponseHeader: function() { return "" },
      send: function() {
        tests.lastFmCalls++
        var self = this
        if (tests.holdResponse) { tests.held = self; return }
        Qt.callLater(function() { tests.complete(self) })
      }, onreadystatechange: null }
    return xhr
  }
  function complete(xhr) {
    xhr.status=200; xhr.responseText=JSON.stringify(response(xhr.url)); xhr.readyState=XMLHttpRequest.DONE
    xhr.onreadystatechange()
  }
  function newAudienceRequest() {
    return {readyState:0,status:0,responseText:"",url:"",aborted:false,onreadystatechange:null,
      open:function(method,url) { this.url=url }, setRequestHeader:function(key,value) {},
      getResponseHeader:function() { return "" }, abort:function() { this.aborted=true },
      send:function() {
        tests.audienceCalls++
        var self=this
        if (tests.holdAudience) { tests.heldAudience=self; return }
        Qt.callLater(function() { tests.completeAudience(self) })
      } }
  }
  function completeAudience(xhr) {
    var id=xhr.url.split("/").pop(),name=Object.keys(counts).filter(function(name) { return artistId(name)===id })[0]
    xhr.status=200; xhr.responseText='<link rel="canonical" href="'+xhr.url+'"/>'
      + (counts[name] === null ? '' : '<div data-testid="monthly-listeners-label">'+counts[name]+' monthly listeners</div>')
    xhr.readyState=XMLHttpRequest.DONE; xhr.onreadystatechange()
  }
  function init() {
    spotifySearches=0; lastFmCalls=0; holdResponse=false; held=null; audienceCalls=0; holdAudience=false; heldAudience=null
    fakeHost.currentUserId="spotify-account"
    fakeHost.settings = { lastFmUsername: "profile", lastFmApiKey: "0123456789abcdef0123456789abcdef",
      discoveryObscurity: "Obscure", discoveryAdventure: "Balanced" }
    controller=component.createObject(tests)
    controller.provider.paceMs=1
    controller.provider.xhrFactory=function() { return tests.newRequest() }
    controller.audienceProvider.paceMs=1
    controller.audienceProvider.xhrFactory=function() { return tests.newAudienceRequest() }
    controller.readState("")
  }
  function check(condition,message) { if (!condition) throw new Error(message) }
  function checkPipeline() {
    if (phase === 1) {
      check(controller.items.length === 5 && controller.items.every(function(item) { return item.discoveryMonthlyListeners < 50000 }),"Underground ceiling failed")
      phase=2
      fakeHost.settings=Object.assign({},fakeHost.settings,{discoveryObscurity:"Deep underground"})
      completion.start(); return
    }
    if (phase === 2) {
      check(controller.items.length === 3 && controller.items.every(function(item) { return item.discoveryMonthlyListeners < 10000 }),"Deep ceiling failed")
      phase=3
      controller.destroy(); init()
      holdAudience=true; controller.ensure(false)
      audienceCancellation.start(); return
    }
    check(controller.items.length === 6,"Feed did not return six verified diverse matches: " + controller.items.length + " " + controller.message
      + " picks="+controller.items.map(function(item) { return item.discoveryArtist }).join(",")
      + " verified="+controller.verifiedArtists.map(function(item) { return item.name }).join(","))
    check(controller.items.every(function(item) { return item.discoveryReason.indexOf("Spotify monthly listeners") >= 0
      && item.discoveryMonthlyListeners < 200000 }),"Strict ceiling or explanation missing")
    check(!controller.items.some(function(item) { return ["Ceiling","Unknown"].indexOf(item.discoveryArtist) >= 0 }),"Oversized/unknown artist leaked")
    check(controller.items.some(function(item) { return item.discoveryArtist === "Deep find" }),"Verified small artist did not open a deeper path")
    check(controller.items.filter(function(item) { return item.discoveryArtist === "Collab" })[0].name === "New three","Mainstream collaboration leaked")
    check(new Set(controller.items.map(function(item) { return item.discoverySpotifyArtistId })).size === controller.items.length,"Repeated artist leaked")
    check(!controller.items.some(function(item) { return item.discoveryArtist === "Artist A" && ["Heard","Loved"].indexOf(item.name) >= 0 }),"Known track leaked")
    var count=spotifySearches, calls=lastFmCalls
    controller.ensure(false)
    check(spotifySearches === count && lastFmCalls === calls,"Fresh cache made requests")
    var item=controller.items[0]
    controller.rate(item,"less")
    check(controller.items.length === 5 && controller.feedback[item.discoveryKey].rating === "less","Feedback did not hide track")
    clock+=86400000
    check(!controller.validStoredItem(controller.items[0]),"Expired listener evidence remained valid")
    controller.destroy()
    init()
    holdResponse=true
    controller.ensure(false)
    check(controller.loading,"Pipeline did not begin")
    fakeHost.currentUserId="different-account"
    check(held.aborted,"Account switch failed to abort provider")
    complete(held)
    check(controller.items.length === 0 && Object.keys(controller.history).length === 0 && !controller.loading,"Late response leaked account data")
    controller.readState(JSON.stringify({version:1,scope:"someone-else",history:{ "$leak":100 },items:[]}))
    check(Object.keys(controller.history).length === 0,"State from another account leaked")
    controller.feedback={ "$x": { rating:"less", at: clock } }
    controller.clearHistory()
    check(Object.keys(controller.feedback).length === 0 && controller.loadedAt === 0,"Clear retained feedback")
    controller.destroy(); init()
    phase=1
    fakeHost.settings=Object.assign({},fakeHost.settings,{discoveryObscurity:"Underground"})
    controller.ensure(false); completion.start()
  }
  Timer {
    id: audienceCancellation
    interval: 10
    repeat: true
    property int ticks: 0
    onTriggered: {
      if (++ticks > 500) throw new Error("Audience cancellation timed out")
      if (!tests.heldAudience) return
      stop()
      fakeHost.currentUserId="another-account"
      tests.check(tests.heldAudience.aborted,"Account switch did not abort public audience request")
      tests.completeAudience(tests.heldAudience)
      tests.check(!tests.controller.items.length && !Object.keys(tests.controller.audienceProvider.cache).length,"Late audience response leaked")
      tests.controller.destroy()
      tests.controller=component.createObject(tests)
      tests.controller.readState(JSON.stringify({version:1,scope:"profile|another-account",loadedAt:tests.clock,
        fingerprint:"Underground|Close",items:[{type:"track",uri:"spotify:track:old"}],history:{"$old":42},feedback:{}}))
      tests.check(!tests.controller.items.length && !tests.controller.loadedAt && tests.controller.history["$old"]===42,
        "Old Last.fm feed was not invalidated while preserving history")
      console.log("DISCOVERY_PIPELINE_PASS")
      Qt.quit()
    }
  }
  Timer {
    interval: 20
    running: true
    onTriggered: { tests.init(); tests.controller.ensure(false); completion.start() }
  }
  Timer {
    id: completion
    interval: 10
    repeat: true
    property int ticks: 0
    onTriggered: {
      ticks++
      if (ticks > 500) throw new Error("Discovery pipeline timed out: " + tests.controller.message)
      if (!tests.controller.loading) { stop(); tests.checkPipeline() }
    }
  }
}
