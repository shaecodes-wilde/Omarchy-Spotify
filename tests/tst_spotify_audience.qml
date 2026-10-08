import QtQuick
import QtTest
import ".." as Plugin

TestCase {
  id: tests
  name: "SpotifyAudienceTransport"
  property var requests: []
  property double clock: 1800000000000
  property int callbacks: 0
  property var record: null
  property string lastError: ""
  readonly property string artistId: "abcdefghijklmnopqrstuv"
  Component {
    id: component
    Plugin.SpotifyAudience {
      paceMs: 1
      now: function() { return tests.clock }
      xhrFactory: function() { return tests.newRequest() }
    }
  }
  function newRequest() {
    var xhr = { readyState:0, status:0, responseText:"", aborted:false, headers:{},url:"",onreadystatechange:null,
      open:function(method,url) { this.url=url }, send:function() {}, abort:function() { this.aborted=true },
      setRequestHeader:function(key,value) { this.headers[key]=value }, getResponseHeader:function() { return "60" } }
    requests.push(xhr); return xhr
  }
  function respond(xhr,status,count) {
    xhr.status=status
    xhr.responseText='<link rel="canonical" href="'+xhr.url+'"/>'
      + '<div data-testid="monthly-listeners-label">'+count+' monthly listeners</div>'
    xhr.readyState=XMLHttpRequest.DONE; xhr.onreadystatechange()
  }
  function receive(value,error,reason) { callbacks++; record=value; lastError=error }
  function init() { requests=[]; callbacks=0; record=null; lastError=""; clock=1800000000000 }
  function test_exactPublicPageAndDailyCache() {
    var api=createTemporaryObject(component,tests)
    api.request(artistId,receive)
    compare(requests[0].url,"https://open.spotify.com/artist/"+artistId)
    verify(!requests[0].headers.Authorization)
    respond(requests[0],200,"199,999")
    compare(record.listeners,199999); compare(record.artistId,artistId)
    api.request(artistId,receive); compare(requests.length,1); compare(callbacks,2)
    clock+=86400000
    api.request(artistId,receive)
    tryVerify(function() { return requests.length===2 })
    respond(requests[1],200,"200,000"); compare(record.listeners,200000)
  }
  function test_missingAndRoundedCountsStayUnknown() {
    var api=createTemporaryObject(component,tests)
    api.request(artistId,receive); respond(requests[0],200,"199.9K")
    compare(record,null); compare(Object.keys(api.cache).length,0)
    api.request("not-an-artist-id",receive); compare(requests.length,1)
  }
  function test_rateLimitHasCooldownAndNoRetryLoop() {
    var api=createTemporaryObject(component,tests)
    api.request(artistId,receive); respond(requests[0],429,"10")
    api.request("ABCDEFGHIJKLMNOPQRSTUV",receive)
    compare(requests.length,1); compare(callbacks,2)
    verify(lastError.indexOf("limiting")>=0)
    verify(api.cooldownUntil>=clock+60000)
  }
  function test_cancelDiscardsLateResponses() {
    var api=createTemporaryObject(component,tests)
    api.request(artistId,receive); api.cancelAll()
    verify(requests[0].aborted)
    respond(requests[0],200,"10")
    compare(callbacks,0); compare(Object.keys(api.cache).length,0)
  }
  function test_timeoutAndNetworkFailure() {
    var api=createTemporaryObject(component,tests,{requestTimeoutMs:10})
    api.request(artistId,receive)
    tryCompare(tests,"callbacks",1); verify(requests[0].aborted); verify(lastError.indexOf("timed out")>=0)
    api.request(artistId,receive)
    tryVerify(function() { return requests.length===2 })
    respond(requests[1],0,""); compare(record,null); verify(lastError.indexOf("unavailable")>=0)
  }
  function test_expiredFutureAndWrongSourceRecordsAreRejected() {
    var api=createTemporaryObject(component,tests)
    var value={artistId:artistId,listeners:100,at:clock,source:"spotify-public-artist-page"}
    verify(api.fresh(value,artistId))
    value.at=clock+1; verify(!api.fresh(value,artistId))
    value.at=clock-86400000; verify(!api.fresh(value,artistId))
    value.at=clock; value.source="lastfm"; verify(!api.fresh(value,artistId))
  }
}
