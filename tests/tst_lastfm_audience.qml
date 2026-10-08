import QtQuick
import QtTest
import ".." as Plugin

TestCase {
  id: tests
  name: "LastFmTotalAudience"
  property var requests: []
  property double clock: 1800000000000
  property int callbacks: 0
  property var record: null
  property string lastError: ""
  property string lastReason: ""
  QtObject {
    id: fakeApi
    function request(method,params,callback,freshness) {
      tests.requests.push({method:method,params:params,callback:callback,freshness:freshness})
    }
  }
  Component {
    id: component
    Plugin.LastFmAudience { api: fakeApi; now: function() { return tests.clock } }
  }
  function receive(value,error,reason) { callbacks++; record=value; lastError=error; lastReason=reason }
  function respond(request,count,name) { request.callback({artist:{name:name || request.params.artist,stats:{listeners:count}}},"") }
  function init() { requests=[]; callbacks=0; record=null; lastError=""; lastReason=""; clock=1800000000000 }

  function test_usesArtistTotalAndDailyCache() {
    var audience=createTemporaryObject(component,tests)
    audience.request("Small",receive)
    compare(requests[0].method,"artist.getInfo")
    compare(requests[0].params.autocorrect,0)
    compare(requests[0].freshness,86400000)
    verify(requests[0].params.period === undefined)
    respond(requests[0],"199999")
    compare(record.listeners,199999); compare(record.source,"lastfm-artist-total")
    audience.request("SMALL",receive); compare(requests.length,1); compare(callbacks,2)
    clock+=86400000
    audience.request("Small",receive); compare(requests.length,2)
    respond(requests[1],"200000"); compare(record.listeners,200000)
  }
  function test_missingMalformedOrWrongProfileStaysUnknown() {
    var audience=createTemporaryObject(component,tests)
    audience.request("Small",receive); respond(requests[0],null)
    compare(record,null); compare(lastReason,"unknown")
    audience.request("Small",receive); respond(requests[1],"100","Other")
    compare(record,null); compare(Object.keys(audience.cache).length,0)
    audience.request("",receive); compare(requests.length,2)
  }
  function test_providerFailuresRemainVisibleAndNotFoundIsUnknown() {
    var audience=createTemporaryObject(component,tests)
    audience.request("Small",receive)
    requests[0].callback(null,"Last.fm is limiting requests. Try again in a minute.")
    compare(record,null); compare(lastReason,"unavailable"); verify(lastError.indexOf("limiting")>=0)
    audience.request("Missing",receive)
    requests[1].callback(null,"Last.fm could not find that profile or artist.")
    compare(lastError,""); compare(lastReason,"unknown")
  }
  function test_cancelIgnoresLateProviderResponses() {
    var audience=createTemporaryObject(component,tests)
    audience.request("Small",receive); audience.cancelAll()
    respond(requests[0],"10")
    compare(callbacks,0); compare(Object.keys(audience.cache).length,0)
  }
  function test_freshRejectsSpotifyMonthlyFutureAndExpiredEvidence() {
    var audience=createTemporaryObject(component,tests)
    var value={artistKey:"$small",listeners:100,at:clock,source:"lastfm-artist-total"}
    verify(audience.fresh(value,"Small"))
    verify(!audience.fresh(value,"Other"))
    value.at=clock+1; verify(!audience.fresh(value,"Small"))
    value.at=clock-86400000; verify(!audience.fresh(value,"Small"))
    value.at=clock; value.source="spotify-public-artist-page"; verify(!audience.fresh(value,"Small"))
  }
}
