import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

ScrollView {
  id: overview
  required property var controller
  clip: true
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

  Column {
    width: overview.availableWidth
    spacing: Style.space(10)
    Text {
      width: parent.width
      text: "Pick up where you left off"
      color: controller.foreground
      font.family: controller.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }
    Flow {
      width: parent.width
      spacing: Style.space(5)
      Button {
        text: "Liked Songs"
        iconText: "󰋑"
        foreground: controller.foreground
        onClicked: { controller.libraryType = "tracks"; controller.chooseTab("library") }
      }
      Repeater {
        model: controller.service ? controller.service.sidebarPlaylists().slice(0, 4) : []
        Button {
          required property var modelData
          text: modelData.name || "Playlist"
          foreground: controller.foreground
          onClicked: controller.openItem(modelData)
        }
      }
    }
    Repeater {
      model: [
        {type:"recent", label:"Recently played"},
        {type:"saved", label:"From your liked songs"},
        {type:"gems", label:"Hidden gems"}
      ]
      Column {
        required property var modelData
        width: parent.width
        spacing: Style.space(5)
        readonly property var items: !controller.service ? [] : modelData.type === "saved"
          ? controller.service.libraryItems("tracks").slice(0, 3)
          : controller.service.homeItems(modelData.type).slice(0, 3)
        Row {
          width: parent.width
          Text {
            width: Math.max(40, parent.width - shelfMore.width)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: controller.foreground
            font.family: controller.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Button {
            id: shelfMore
            text: modelData.type === "gems" && !parent.parent.items.length ? "Discover" : "Show all"
            foreground: controller.foreground
            onClicked: {
              if (modelData.type === "saved") { controller.libraryType = "tracks"; controller.chooseTab("library") }
              else controller.homeType = modelData.type
            }
          }
        }
        Text {
          width: parent.width
          visible: parent.items.length === 0
          text: modelData.type === "gems" ? "Open Hidden gems to start a discovery session."
            : "Open this collection to load your music."
          color: controller.muted
          font.family: controller.fontFamily
          font.pixelSize: Style.font.caption
        }
        MediaCollection {
          navigationOwner: controller
          enableSelection: false
          width: parent.width
          height: parent.items.length ? Style.space(66) * parent.items.length : 0
          visible: height > 0
          sourceItems: parent.items
          service: controller.service
          onBatchQueueRequested: function(items) { if (controller.service) controller.service.addItemsToQueue(items) }
          onListInteracted: controller.setPanelCursor("page", keyboardListId)
          onBatchPlaylistRequested: function(items) { controller.openPlaylistPicker(items) }
          onBatchSaveRequested: function(items) { if (controller.service) controller.service.toggleSavedItems(items) }
          onBatchRemoveRequested: function(items) { if (controller.service) controller.service.removePlaylistItems(items, actionPlaylist) }
          stateKey: "home:overview:" + modelData.type
          keyboardListId: "list-home-" + modelData.type
          showFilter: false
          showSort: false
          showQueue: true
          showSave: true
          browseContexts: true
          onActivated: function(item, items, uri) { controller.activateMedia(item, items, uri) }
          onOpened: function(item) { controller.openItem(item) }
          onQueued: function(item) { controller.service.addToQueue(item) }
          onPlaylistRequested: function(item) { controller.openPlaylistPicker(item) }
          onSaveToggled: function(item) { controller.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
            controller.openMediaContext(item, x, y, items, uri, index, playbackUri)
          }
        }
      }
    }
  }
}
