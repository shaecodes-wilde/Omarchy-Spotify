import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  Plugin.Service { id: service }
  function check(value, message) { if (!value) throw new Error(message) }
  function rows(count) { var result = []; for (var i=0;i<count;i++) result.push({id:String(i)}); return result }
  Timer {
    interval: 100; running: true
    onTriggered: {
      service.setUiVisible("fixture", true)
      service.activeView = "library"
      service.activeLibraryKind = "tracks"
      service.savedTracks = rows(180)
      service.savedTracksNext = "/me/tracks?offset=180"
      service.savedTracksLoaded = true
      service.retainLibraryPage("tracks")
      service.savedTracks = rows(10000)
      service.savedTracksNext = ""
      service.trimInactiveLibraryCollections()
      check(service.savedTracks.length === 10000, "Visible collection was truncated")
      service.activeLibraryKind = "albums"
      service.trimInactiveLibraryCollections()
      check(service.savedTracks.length === 180 && service.savedTracksLoaded
        && service.savedTracksNext === "/me/tracks?offset=180", "Inactive page/cursor did not resume together")
      service.savedAlbums = rows(10000)
      service.savedAlbumsLoaded = true
      service.activeView = "search"
      check(!service.savedAlbums.length && !service.savedAlbumsLoaded && !service.savedAlbumsNext,
        "Missing retained page must reset loaded state")
      check(!service.discoveryVisible && !service.discovery.active, "Cold service started discovery")
      service.loadHiddenGems(true)
      check(!service.discovery.requested && !service.discovery.loading, "Closed refresh scheduled discovery")
      service.setDiscoverySurfaceVisible("one", true)
      service.setDiscoverySurfaceVisible("two", true)
      check(service.discovery.active, "Visible discovery was disabled")
      service.setDiscoverySurfaceVisible("one", false)
      check(service.discovery.active, "One closing surface cancelled another")
      service.setDiscoverySurfaceVisible("two", false)
      check(!service.discovery.active && !service.discovery.requested, "Last closing surface did not cancel")
      service.activeView = "library"
      service.activeLibraryKind = "tracks"
      service.savedTracks = rows(10000)
      service.playlistItems = rows(200)
      service.playlistItemsNext = "/playlists/one/items?offset=200"
      service.retainDetailPage("playlistItems", "playlistItemsNext", "retainedPlaylistPage")
      service.playlistItems = rows(10000)
      service.playlistItemsNext = ""
      service.detailItems = rows(150)
      service.detailNext = "/albums/one/tracks?offset=150"
      service.retainDetailPage("detailItems", "detailNext", "retainedDetailPage")
      service.detailItems = rows(1000)
      service.detailNext = ""
      service.setUiVisible("fixture", false)
      check(service.playlistItems.length === 200 && service.playlistItemsNext === "/playlists/one/items?offset=200"
        && service.playlistRestoreTargetCount === 10000, "Closed playlist lost its boundary or restore target")
      check(service.detailItems.length === 150 && service.detailNext === "/albums/one/tracks?offset=150",
        "Closed detail lost its page boundary")
      check(service.savedTracks.length === 180, "Closing all surfaces retained the full active collection")
      service.clearData()
      check(!service.retainedPlaylistPage && !service.retainedDetailPage && !Object.keys(service.retainedLibraryPages).length, "Account reset retained library snapshots")
      console.log("RESOURCE_POLICY_PASS")
      Qt.quit()
    }
  }
}
