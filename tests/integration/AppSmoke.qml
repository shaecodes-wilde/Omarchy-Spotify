import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  QtObject {
    id: scopedShell
    property var barConfig: ({ layout: { left: [{ id: "quickshell.spotify",
      clientId: "invalid", deviceName: "Scoped receiver" }] } })
  }
  Plugin.Service { id: spotifyService }
  Plugin.Panel { id: panel; service: spotifyService; width: 1280; height: 800 }
  Plugin.BarWidget { id: widget }
  Timer {
    interval: 20
    running: true
    onTriggered: {
      spotifyService.auth.customClientId = "invalid"
      if (spotifyService.normalizedSettings({discoveryObscurity:"Balanced"}).discoveryObscurity !== "Obscure"
          || spotifyService.normalizedSettings({}).discoveryObscurity !== "Obscure")
        throw new Error("Discovery default or legacy setting migration failed")
      spotifyService.search("smoke-test", "track")
      if (spotifyService.searchLoading || !spotifyService.searchError)
        throw new Error("Search service did not return the authorization error")
      if (!panel.primaryNavigationItems().some(function(item) { return item.id === "search" }))
        throw new Error("Search navigation is missing")
      spotifyService.clearSearch()
      if (spotifyService.searchQuery !== "") throw new Error("Search state did not clear")
      spotifyService.topTracks = [{ id: "song", albumItem: {
        type: "album", id: "album", uri: "spotify:album:album", name: "Album"
      } }]
      if (spotifyService.homeItems("albums").length !== 1)
        throw new Error("Top albums did not update from top songs")
      if (typeof panel !== "undefined") {
        spotifyService.sessionState = { homeType: "albums" }
        panel.restoreUiState()
        if (panel.homeType !== "albums" || panel.pageCursorActions().indexOf("home-albums") < 0)
          throw new Error("Top albums navigation or restoration is missing")
      }
      spotifyService.shell = scopedShell
      spotifyService.syncSettings()
      if (spotifyService.settings.clientId !== "invalid"
          || spotifyService.deviceName !== "Scoped receiver")
        throw new Error("Scoped shell settings did not load")
      scopedShell.barConfig = { layout: { left: [{ id: "quickshell.spotify",
        clientId: "invalid", deviceName: "Updated receiver" }] } }
      spotifyService.sessionState = { homeType: "gems" }
      panel.restoreUiState()
      if (panel.homeType !== "gems" || panel.pageCursorActions().indexOf("home-gems") < 0)
        throw new Error("Hidden gems restoration or navigation is missing")
      panel.currentTab = "setup"
      finishSmoke.start()
    }
  }
  Timer {
    id: finishSmoke
    interval: 20
    onTriggered: {
      if (spotifyService.deviceName !== "Updated receiver")
        throw new Error("Scoped shell settings did not update live")
      panel.currentTab = "home"
      panel.homeType = "gems"
      finishUi.start()
    }
  }
  Timer {
    id: finishUi
    interval: 100
    onTriggered: {
      var status = JSON.parse(panel.discoveryStatus())
      if (!status.available || status.apiKeyConfigured || status.homeType !== "gems"
          || status.listenerMetric !== "Last.fm total listeners" || status.listenerCeiling !== 200000)
        throw new Error("Discovery diagnostics or home page did not load")
      console.log("APP_SMOKE_PASS")
      Qt.quit()
    }
  }
}
