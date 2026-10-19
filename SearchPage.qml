import QtQuick
import qs.Commons
import qs.Ui
import "Api.js" as Api

    Item {
      id: searchRoot
      required property var controller
      readonly property var panel: controller
      component KeyHint: DesktopKeyHint { controller: searchRoot.controller }

      readonly property var items: panel.service
        ? panel.service.searchItems(panel.searchType) : []
      readonly property string errorText: panel.service
        ? String(panel.service.searchError || "") : ""

      Component.onDestruction: {
        if (panel.service) panel.service.cancelSearch(false)
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        Flow {
          id: searchTypes
          width: parent.width
          spacing: Style.space(3)

          Repeater {
            model: [
              { type: "all", label: "All" },
              { type: "track", label: "Songs" },
              { type: "artist", label: "Artists" },
              { type: "album", label: "Albums" },
              { type: "playlist", label: "Playlists" },
              { type: "show", label: "Podcasts" },
              { type: "episode", label: "Episodes" },
              { type: "audiobook", label: "Books" }
            ]

            Button {
              required property var modelData
              text: modelData.label
              foreground: panel.foreground
              selected: panel.searchType === modelData.type
              focusable: false
              horizontalPadding: Style.space(7)
              hasCursor: panel.cursorOn("page", "search-" + modelData.type)
              onClicked: panel.selectSearchType(modelData.type)
              onHovered: function(on) {
                if (on) panel.setPanelCursor("page", "search-" + modelData.type)
              }
              KeyHint { region: "page"; action: "search-" + modelData.type }
            }
          }
        }

        Row {
          id: searchStatus
          width: parent.width
          height: visible ? Math.max(searchErrorText.implicitHeight,
            retrySearch.implicitHeight) : 0
          spacing: Style.space(7)
          visible: panel.searchText.trim() !== "" && searchRoot.errorText !== ""

          Text {
            id: searchErrorText
            width: Math.max(40, parent.width - retrySearch.width - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            text: panel.searchCooldownSeconds > 0 && panel.service
              ? panel.service.searchProgressText(panel.searchClock) : searchRoot.errorText
            color: Color.urgent
            font.family: panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Button {
            id: retrySearch
            enabled: panel.searchCooldownSeconds === 0
            hasCursor: panel.cursorOn("page", "retry-search")
            onHovered: function(on) { if (on) panel.setPanelCursor("page", "retry-search") }
            KeyHint { region: "page"; action: "retry-search" }
            text: "Retry"
            iconText: "󰑐"
            foreground: panel.foreground
            onClicked: if (panel.service)
              panel.requestSearch(panel.searchText, panel.searchType, true)
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(7)
          visible: panel.searchText.trim() === ""

          Row {
            width: parent.width

            Text {
              text: "RECENT SEARCHES"
              color: panel.foreground
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Item { width: Math.max(0, parent.width - clearHistory.width - Style.space(120)); height: 1 }
            Button {
              id: clearHistory
              text: "Clear"
              foreground: panel.foreground
              visible: panel.service && panel.service.searchHistory.length > 0
              onClicked: panel.service.clearSearchHistory()
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(5)

            Repeater {
              model: panel.service ? panel.service.searchHistory : []
              Button {
                required property string modelData
                text: modelData
                iconText: "󰍉"
                foreground: panel.foreground
                onClicked: {
                  panel.searchText = modelData
                  panel.requestSearch(modelData, panel.searchType)
                  Qt.callLater(function() { panel.focusSearch() })
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: !panel.service || panel.service.searchHistory.length === 0
            text: "Type a title, artist, album, playlist, podcast, episode, or audiobook."
            color: panel.muted
            font.family: panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Loader {
          width: parent.width
          height: active ? Math.max(40, parent.height - searchTypes.height - searchStatus.height - parent.spacing * 2) : 0
          active: panel.searchText.trim() !== "" && panel.searchType === "all"
          visible: active
          sourceComponent: Component { MixedSearchResults { controller: searchRoot.controller } }
        }
        Loader {
          width: parent.width
          height: active ? Math.max(40, parent.height - searchTypes.height - searchStatus.height - parent.spacing * 2) : 0
          active: panel.searchType !== "all" && panel.searchText.trim() !== ""
            && (searchRoot.errorText === "" || searchRoot.items.length > 0)
          visible: active
          sourceComponent: Component {
        MediaCollection {
          id: resultsView
          anchors.fill: parent
          service: panel.service
          onBatchQueueRequested: function(items) { if (panel.service) panel.service.addItemsToQueue(items) }
          onBatchPlaylistRequested: function(items) { panel.openPlaylistPicker(items) }
          onBatchSaveRequested: function(items) { if (panel.service) panel.service.toggleSavedItems(items) }
          onBatchRemoveRequested: function(items) { if (panel.service) panel.service.removePlaylistItems(items, actionPlaylist) }
          sourceItems: searchRoot.items
          showFilter: false
          showQueue: true
          showSave: true
          browseContexts: true
          loading: panel.service && panel.service.searchLoading
          hasMore: panel.service && panel.service.searchNext(panel.searchType) !== ""
          restoredContentY: panel.scrollFor("search:" + panel.searchType)
          stateKey: "search:" + panel.searchType
          emptyMessage: panel.service && panel.service.searchLoading
            ? panel.service.searchProgressText(panel.searchClock) : "No " + Api.searchTypeLabel(panel.searchType)
              + " results."
          onActivated: function(item, items, uri) {
            panel.activateMedia(item, items, uri)
          }
          onOpened: function(item) { panel.openItem(item) }
          onQueued: function(item) { if (panel.service) panel.service.addToQueue(item) }
          onPlaylistRequested: function(item) { panel.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (panel.service) panel.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
            panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
          }
          onLoadMoreRequested: if (panel.service) panel.service.loadMoreSearch(panel.searchType)
          onViewStateChanged: function(filter, sort, y) {
            panel.rememberScroll("search:" + panel.searchType, y)
          }
        }
          }
        }
      }

    }
