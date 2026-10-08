import QtQuick
import QtTest
import ".." as Plugin

TestCase {
  id: tests
  name: "LastFmTransport"
  property var requests: []
  property double clock: 1000
  property int callbacks: 0
  property string lastError: ""

  Component {
    id: component
    Plugin.LastFmApi {
      apiKey: "0123456789abcdef0123456789abcdef"
      paceMs: 1
      now: function() { return tests.clock }
      xhrFactory: function() { return tests.newRequest() }
    }
  }

  function newRequest() {
    var xhr = { readyState: 0, status: 0, responseText: "", aborted: false,
      url: "", onreadystatechange: null,
      open: function(method,url) { this.url = url },
      send: function() {},
      abort: function() { this.aborted = true },
      getResponseHeader: function() { return "60" }
    }
    requests.push(xhr)
    return xhr
  }
  function respond(xhr,status,payload) {
    xhr.status = status; xhr.responseText = JSON.stringify(payload)
    xhr.readyState = XMLHttpRequest.DONE
    xhr.onreadystatechange()
  }
  function receive(payload,error) { callbacks++; lastError = error }
  function init() { requests = []; callbacks = 0; lastError = ""; clock = 1000 }

  function test_missingKey_doesNotSend() {
    var api = createTemporaryObject(component,tests)
    api.apiKey = ""
    api.request("user.getRecentTracks",{ user: "profile" },receive)
    compare(requests.length,0)
    compare(callbacks,1)
    verify(lastError.indexOf("API key") >= 0)
  }

  function test_success_cache_andProviderErrorWithHttp200() {
    var api = createTemporaryObject(component,tests)
    api.request("artist.getInfo",{ artist: "A" },receive)
    respond(requests[0],200,{ artist: { name: "A" } })
    api.request("artist.getInfo",{ artist: "A" },receive)
    compare(requests.length,1)
    compare(callbacks,2)
    api.request("artist.getInfo",{ artist: "B" },receive)
    tryCompare(api,"active",null)
    tryVerify(function() { return requests.length === 2 })
    respond(requests[1],200,{ error: 10, message: "secret-looking provider message" })
    verify(lastError.indexOf("API key") >= 0)
    verify(lastError.indexOf("secret-looking") < 0)
  }

  function test_rateLimit_blocksNewRequestsWithoutRetryLoop() {
    var api = createTemporaryObject(component,tests)
    api.request("artist.getInfo",{ artist: "A" },receive)
    respond(requests[0],200,{ error: 29 })
    api.request("artist.getInfo",{ artist: "B" },receive)
    compare(requests.length,1)
    compare(callbacks,2)
    verify(api.cooldownUntil >= 61000)
  }

  function test_cancel_ignoresLateResponses() {
    var api = createTemporaryObject(component,tests)
    api.request("artist.getInfo",{ artist: "A" },receive)
    api.cancelAll()
    verify(requests[0].aborted)
    respond(requests[0],200,{ artist: { name: "A" } })
    compare(callbacks,0)
    compare(Object.keys(api.cache).length,0)
  }

  function test_timeout_andReadOnlyMethods() {
    var api = createTemporaryObject(component,tests,{ requestTimeoutMs: 10 })
    api.request("track.scrobble",{},receive)
    compare(requests.length,0)
    verify(lastError.indexOf("Unsupported") >= 0)
    callbacks = 0
    api.request("artist.getInfo",{ artist: "A" },receive)
    tryCompare(tests,"callbacks",1)
    verify(requests[0].aborted)
    verify(lastError.indexOf("too long") >= 0)
  }
}
