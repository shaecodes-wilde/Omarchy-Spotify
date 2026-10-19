import QtQuick
import QtTest
import "../Navigation.js" as Navigation

TestCase {
  name: "Navigation"
  function test_snapshot_retains_deep_context_and_state() {
    var route = Navigation.snapshot({tab:"detail", detailItem:{id:"p", type:"playlist", name:"P", items:[1,2]},
      detailItemCount:750, detailFilter:"song", detailSort:"name", focusIndex:630,
      focusRegion:"page", focusAction:"list", scrollPositions:{"detail:playlist:p":24000}})
    compare(route.detailItemCount, 750)
    compare(route.focusIndex, 630)
    compare(route.detailFilter, "song")
    compare(route.scrollPositions["detail:playlist:p"], 24000)
    verify(route.detailItem.items === undefined)
  }
  function test_history_and_session_are_bounded() {
    var history = []
    for (var i=0; i<100; i++) history = Navigation.push(history, {tab:"detail", detailItem:{id:String(i),type:"playlist",description:"a".repeat(2000)}, detailItemCount:1000})
    compare(history.length, Navigation.HISTORY_LIMIT)
    var state = Navigation.session({tab:"home", sidebarWidth:10000}, history, history)
    verify(JSON.stringify(state).length <= Navigation.SESSION_LIMIT)
    verify(state.backHistory.length > 0)
    compare(state.sidebarWidth, 360)
  }
  function test_route_depth_is_scalar_and_bounded() {
    var route = Navigation.snapshot({tab:"library", libraryType:"albums", libraryItemCount:750,
      searchText:"artist", searchType:"track", searchItemCount:300})
    compare(route.libraryItemCount, 750)
    compare(route.searchItemCount, 300)
    compare(Navigation.snapshot({libraryItemCount:90000, searchItemCount:-1}).libraryItemCount, 10000)
    compare(Navigation.snapshot({libraryItemCount:90000, searchItemCount:-1}).searchItemCount, 0)
  }
  function test_pins_stable_and_bounded() {
    var items = [{id:"a"}, {id:"b"}, {id:"c"}]
    var sorted = Navigation.pinnedPlaylists(items, ["c", "c"])
    compare(sorted[0].id, "c")
    compare(sorted[1].id, "a")
    compare(items[0].id, "a")
    compare(Navigation.pins(["a", "a", "b"]).length, 2)
  }
  function test_oversized_current_route_keeps_session() {
    var value = {tab:"detail"}
    for (var i=0; i<Navigation.TEXT_FIELDS.length; i++) value[Navigation.TEXT_FIELDS[i]] = "x".repeat(4000)
    value.detailItem = {id:"p", type:"playlist", name:"x".repeat(4000), subtitle:"x".repeat(4000), description:"x".repeat(4000), uri:"spotify:playlist:p"}
    value.selectedPlaylist = value.detailItem
    value.lastRadioPlaylist = value.detailItem
    value.playlistPins = Array.from({length:32}, function(_, index) { return String(index) + "x".repeat(120) })
    var state = Navigation.session(value, [], [])
    verify(JSON.stringify(state).length <= Navigation.SESSION_LIMIT)
    compare(state.detailItem.id, "p")
  }
  function test_adversarial_session_always_fits() {
    var route = {tab:"detail", scrollPositions:{}, playlistPins:[]}
    for (var f=0; f<Navigation.TEXT_FIELDS.length; f++) route[Navigation.TEXT_FIELDS[f]] = "z".repeat(5000)
    var item = {id:"i".repeat(128), type:"playlist"}
    var fields = ["name", "subtitle", "uri", "imageUrl", "description", "ownerId"]
    for (var c=0; c<fields.length; c++) item[fields[c]] = "m".repeat(5000)
    route.detailItem = item; route.selectedPlaylist = item; route.lastRadioPlaylist = item
    for (var p=0; p<32; p++) route.playlistPins.push(String(p) + "p".repeat(126))
    for (var s=0; s<128; s++) route.scrollPositions[String(s) + "s".repeat(176)] = 10000000
    var state = Navigation.session(route, Array(20).fill(route), Array(20).fill(route))
    verify(JSON.stringify(state).length <= Navigation.SESSION_LIMIT)
    compare(state.detailItem.id, item.id)
  }
  function test_link_navigation() {
    compare(Navigation.spotifyLink("spotify:playlist:abc123").type, "playlist")
    compare(Navigation.spotifyLink("https://open.spotify.com/intl-en/album/ABC?si=token").uri, "spotify:album:ABC")
    compare(Navigation.spotifyLink("https://evil.example/album/ABC"), null)
    compare(Navigation.spotifyLink("https://open.spotify.com.evil.example/album/ABC"), null)
    compare(Navigation.spotifyLink("ordinary text"), null)
  }
}
