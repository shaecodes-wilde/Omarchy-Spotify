import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Navigation.js" as Navigation

ScrollView {
  id: pane
  required property var controller
  readonly property var service: controller.service
  clip: true
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

  Column {
    width: pane.availableWidth
    spacing: Style.space(10)
    Text {
      width: parent.width
      text: "NOW PLAYING"
      color: controller.foreground
      font.family: controller.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    RetryImage {
      width: parent.width
      height: width
      requestedSource: pane.service && pane.service.artworkEnabled ? pane.service.artUrl : ""
      sourceSize.width: 256
      sourceSize.height: 256
      asynchronous: true
      fillMode: Image.PreserveAspectFit
      visible: pane.service && pane.service.artworkEnabled && requestedSource !== ""
    }
    Text {
      width: parent.width
      text: pane.service && pane.service.title ? pane.service.title : "Nothing playing"
      color: controller.foreground
      font.family: controller.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      wrapMode: Text.WordWrap
    }
    ArtistLinks {
      width: parent.width
      artists: pane.service ? pane.service.currentArtists : []
      fallbackText: pane.service ? pane.service.artist : ""
      fallbackClickable: pane.service && pane.service.currentArtistContextAvailable
      color: controller.accent
      accent: controller.accent
      font.family: controller.fontFamily
      font.pixelSize: Style.font.body
      onArtistRequested: function(item) { controller.openItem(item) }
      onFallbackRequested: controller.openCurrentArtist()
    }
    Button {
      width: parent.width
      text: pane.service && pane.service.album ? pane.service.album : "Album unavailable"
      foreground: controller.foreground
      leftAlign: true
      enabled: pane.service && pane.service.currentAlbumContextAvailable
      onClicked: controller.openCurrentAlbum()
    }
    Button {
      width: parent.width
      text: "Open playing context"
      foreground: controller.foreground
      enabled: pane.service && !!Navigation.spotifyLink(pane.service.playbackContextUri)
      onClicked: {
        var item = Navigation.spotifyLink(pane.service.playbackContextUri)
        if (item) controller.openItem(item)
      }
    }
    Flow {
      width: parent.width
      spacing: Style.space(5)
      Button {
        text: pane.service && pane.service.currentTrackSaved ? "Liked" : "Like"
        iconText: pane.service && pane.service.currentTrackSaved ? "󰋑" : "󰋕"
        foreground: Color.urgent
        enabled: pane.service && pane.service.currentTrackSaveAvailable
        onClicked: pane.service.toggleCurrentTrackSaved()
      }
      Button {
        text: "Connect"
        iconText: "󰋋"
        foreground: controller.foreground
        onClicked: controller.chooseTab("devices")
      }
      Button {
        text: "Lyrics"
        visible: pane.service && pane.service.lyricsAvailable
        foreground: controller.foreground
        onClicked: controller.openLyrics()
      }
    }
  }
}
