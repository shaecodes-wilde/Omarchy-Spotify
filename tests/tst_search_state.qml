import QtQuick
import QtTest
import ".." as Plugin
import "../Api.js" as Api

TestCase {
  id: testCase
  name: "SearchState"
  property var calls: []
  QtObject {
    id: transport
    function search(term, type, callback) {
      testCase.calls.push({term: term, type: type, callback: callback})
    }
    function cancelSearch() {}
    function abortRequest(handle) { if (handle) handle.aborted = true }
    function request(method, path, query, body, callback) {
      var handle = {path: path, query: query, callback: callback, aborted: false}
      testCase.calls.push(handle)
      return handle
    }
  }
  Component { id: controller; Plugin.SearchController { api: transport } }
  function init() { calls = [] }
  function result(type, items, next) {
    var groups = Api.searchGroups({}, 128)
    groups[type] = {items: items || [], next: next || "", total: 1000}
    return groups
  }
  function test_pendingAndEmptyResultsAreReused() {
    var state = createTemporaryObject(controller, testCase)
    state.search("hello", "track")
    state.search("hello", "track")
    compare(calls.length, 1)
    calls[0].callback(result("track"), "")
    state.search("hello", "album")
    calls[1].callback(result("album"), "")
    state.search("hello", "track")
    compare(calls.length, 2)
    state.search("hello", "track", true)
    compare(calls.length, 3)
    calls[2].callback(result("track"), "")
    state.search("hello", "album")
    compare(calls.length, 3)
  }
  function test_obsoletePaginationIsAbortedAndIgnored() {
    var state = createTemporaryObject(controller, testCase)
    state.search("first", "track")
    calls[0].callback(result("track", [], "/next"), "")
    state.loadMoreSearch("track")
    var page = calls[1]
    state.search("second", "track")
    verify(page.aborted)
    page.callback(200, {}, "late failure")
    verify(state.searchLoading)
    compare(state.searchError, "")
    state.clearSearch()
    calls[2].callback(result("track"), "")
    compare(state.searchQuery, "")
    compare(state.searchLoadedTypes.track, undefined)
  }
  function test_emptyPageFailureRetriesPageAndAccountChangeClears() {
    var state = createTemporaryObject(controller, testCase)
    state.search("first", "track")
    calls[0].callback(result("track", [], "/next"), "")
    state.loadMoreSearch("track")
    calls[1].callback(500, null, "failed")
    state.retrySearch("track")
    compare(calls[2].path, "/next")
    state.dataSerial++
    verify(calls[2].aborted)
    compare(state.searchQuery, "")
    verify(!state.searchLoading)
  }
  function test_overviewLoadsOnlyThreeFirstPagesAndReusesResults() {
    var state = createTemporaryObject(controller, testCase)
    state.searchAll("hello")
    compare(calls.length, 3)
    compare(calls[0].query.type, "track")
    compare(calls[0].query.limit, 10)
    calls.forEach(function(call) { call.callback(200, {}, "") })
    verify(!state.searchLoading)
    state.searchAll("hello")
    compare(calls.length, 3)
    state.search("hello", "track")
    compare(calls.length, 3)
  }
  function test_overviewCancelsAllRequestsAndIgnoresOldAccount() {
    var state = createTemporaryObject(controller, testCase)
    state.search("first", "all")
    var old = calls.slice()
    state.search("second", "all")
    old.forEach(function(call) {
      verify(call.aborted)
      call.callback(500, null, "stale error")
    })
    compare(state.searchQuery, "second")
    compare(state.searchError, "")
    state.dataSerial++
    calls.slice(3).forEach(function(call) { verify(call.aborted) })
    verify(!state.searchLoading)
  }
  function test_overviewRetriesOnlyFailedCategories() {
    var state = createTemporaryObject(controller, testCase)
    state.searchAll("hello")
    calls[0].callback(200, {}, "")
    calls[1].callback(500, null, "failed")
    calls[2].callback(200, {}, "")
    compare(state.searchError, "failed")
    state.retrySearch("all")
    compare(calls.length, 4)
    compare(calls[3].query.type, "artist")
    calls[3].callback(200, {}, "")
    compare(state.searchError, "")
  }
}
