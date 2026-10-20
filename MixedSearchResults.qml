import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

ScrollView {
  id: mixed
  required property var controller
  clip: true
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

  Column {
    width: mixed.availableWidth
    spacing: Style.space(12)
    Repeater {
      model: [{type:"track", label:"Songs"}, {type:"artist", label:"Artists"}, {type:"album", label:"Albums"}]
      Column {
        required property var modelData
        readonly property var items: controller.service ? controller.service.searchItems(modelData.type).slice(0, 4) : []
        width: parent.width
        spacing: Style.space(5)
        Row {
          width: parent.width
          Text {
            width: Math.max(40, parent.width - showAll.width)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: controller.foreground
            font.family: controller.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Button {
            id: showAll
            text: "Show all"
            foreground: controller.foreground
            onClicked: controller.selectSearchType(modelData.type)
          }
        }
        MediaCollection {
          navigationOwner: controller
          enableSelection: false
          width: parent.width
          height: parent.items.length ? Style.space(66) * parent.items.length : Style.space(44)
          service: controller.service
          onBatchQueueRequested: function(items) { if (controller.service) controller.service.addItemsToQueue(items) }
          onListInteracted: controller.setPanelCursor("page", keyboardListId)
          onBatchPlaylistRequested: function(items) { controller.openPlaylistPicker(items) }
          onBatchSaveRequested: function(items) { if (controller.service) controller.service.toggleSavedItems(items) }
          onBatchRemoveRequested: function(items) { if (controller.service) controller.service.removePlaylistItems(items, actionPlaylist) }
          sourceItems: parent.items
          stateKey: "search:all:" + modelData.type
          keyboardListId: "list-search-" + modelData.type
          showFilter: false
          showSort: false
          showQueue: modelData.type === "track"
          showSave: true
          browseContexts: true
          loading: controller.service && controller.service.searchLoading && !parent.items.length
          emptyMessage: controller.service && controller.service.searchLoading ? "Searching…" : "No matching " + modelData.label.toLowerCase() + "."
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
