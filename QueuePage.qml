import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Api.js" as Api

Item {
  id: queueRoot
  property bool drawer: false
  required property var controller
  readonly property var panel: controller
      readonly property var visibleItems: Api.filteredSorted(
        panel.service ? panel.service.queue : [], panel.queueFilter, "default")

  readonly property string queueSurface: drawer ? "queue-drawer" : "queue-page"
  function updateVisibleMetadata() {
    if (!panel.service || typeof panel.service.setQueueVisibleItems !== "function") return
    if (!panel.opened || !visible || queueList.count === 0) {
      panel.service.setQueueVisibleItems(queueSurface, [])
      return
    }
    var x = Math.max(1, queueList.width / 2)
    var gap = queueList.spacing + 1
    var top = queueList.contentY + 1
    var first = queueList.indexAt(x, top)
    if (first < 0) first = queueList.indexAt(x, top + gap)
    if (first < 0) {
      panel.service.setQueueVisibleItems(queueSurface, [])
      return
    }
    var bottom = Math.min(queueList.contentY + queueList.height - 1,
      queueList.originY + queueList.contentHeight - 1)
    var last = queueList.indexAt(x, bottom)
    if (last < first) last = queueList.indexAt(x, bottom - gap)
    if (last < first) last = first
    panel.service.setQueueVisibleItems(queueSurface, visibleItems.slice(first, Math.min(last + 1, first + 50)))
  }
  onVisibleItemsChanged: Qt.callLater(updateVisibleMetadata)
  onVisibleChanged: Qt.callLater(updateVisibleMetadata)
  Component.onCompleted: Qt.callLater(updateVisibleMetadata)
  Component.onDestruction: {
    if (panel.service && typeof panel.service.setQueueVisibleItems === "function")
      panel.service.setQueueVisibleItems(queueSurface, [])
  }

      Column {
        anchors.fill: parent
        spacing: Style.space(8)

        Row {
          width: parent.width

          Text {
            text: "UP NEXT"
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Item { width: Math.max(0, parent.width - queueRefresh.width - Style.space(80)); height: 1 }

          Button {
            id: queueRefresh
            text: panel.service && panel.service.queueLoading ? "Loading…" : "Refresh"
            iconText: "󰑐"
            foreground: panel.foreground
            enabled: panel.service && !panel.service.queueLoading
            onClicked: panel.service.loadQueue()
          }
        }

        Text {
          id: queueExplanation
          width: parent.width
          text: panel.service ? panel.service.queueUnavailableReason : ""
          visible: text !== ""
          color: panel.muted
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        ListView {
          id: queueList
          objectName: queueRoot.drawer ? "queue-drawer-list" : "page-list"
          width: parent.width
          height: Math.max(60, parent.height - (queueExplanation.visible ? queueExplanation.implicitHeight : 0) - Style.space(52))
          model: queueRoot.visibleItems
          clip: true
          spacing: Style.space(3)
          reuseItems: true
          cacheBuffer: Style.space(140)
          keyNavigationEnabled: false
          Component.onCompleted: contentY = panel.scrollFor("queue")
          onContentYChanged: {
            panel.rememberScroll("queue", contentY)
            Qt.callLater(queueRoot.updateVisibleMetadata)
          }
          onHeightChanged: Qt.callLater(queueRoot.updateVisibleMetadata)
          onCountChanged: Qt.callLater(queueRoot.updateVisibleMetadata)
          highlightFollowsCurrentItem: true
          activeFocusOnTab: false
          ScrollBar.vertical: ScrollBar { }
          Keys.onReturnPressed: function(event) {
            if (!panel.cursorOn("page", "list")) {
              event.accepted = false
              return
            }
            if (currentItem) currentItem.triggerPrimary()
            event.accepted = true
          }
          Keys.onEnterPressed: function(event) {
            if (!panel.cursorOn("page", "list")) {
              event.accepted = false
              return
            }
            if (currentItem) currentItem.triggerPrimary()
            event.accepted = true
          }

          FastScrollHandler { parent: queueList; flickable: queueList }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Style.space(16)
            width: Math.max(80, parent.width - Style.space(24))
            visible: queueList.count === 0
            text: panel.service && panel.service.queueLoading
              ? "Loading the queue…"
              : (panel.queueFilter.trim()
                ? "No matching songs in the queue."
                : "Nothing is queued to play next.")
            color: panel.muted
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          delegate: MediaRow {
            required property var modelData
            required property int index
            itemData: modelData
            foreground: panel.foreground
            accent: panel.accent
            fontFamily: panel.fontFamily
            selected: ListView.isCurrentItem
              && !queueRoot.drawer && panel.cursorOn("page", "list")
            showPlay: panel.service && panel.service.queueCanActivate
            showQueue: false
            showSave: true
            artworkEnabled: !panel.service || panel.service.artworkEnabled
            saved: panel.service && panel.service.isSaved(modelData)
            onActivated: function(item) {
              if (panel.service && panel.service.queueCanActivate) panel.service.activateQueueItem(item)
            }
            onArtistRequested: function(item) { panel.openItem(item) }
            onAlbumRequested: function(item) { panel.openItem(item) }
            onOpenRequested: function(item) { panel.openItem(item) }
            onPlaylistRequested: function(item) { panel.openPlaylistPicker(item) }
            onSaveRequested: function(item) { if (panel.service) panel.service.toggleSaved(item) }
            ShortcutHint {
              active: !queueRoot.drawer && hint !== ""
              navHint: hint
              readonly property string hint: {
                queueList.currentIndex
                queueList.contentY
                panel.panelCursorAction
                panel.panelCursorRegion
                panel.hintCtrlHeld
                return panel.pageListRowHint(index, queueList)
              }
            }
          }
        }
      }
    }
