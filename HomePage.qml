import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: homePage
  required property var controller
  readonly property var panel: controller
  component KeyHint: DesktopKeyHint { controller: homePage.controller }
      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        Flow {
          id: homeTypes
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: [
              { type: "overview", label: "Overview", icon: "󰎆" },
              { type: "gems", label: "Hidden gems", icon: "󰎆" },
              { type: "recent", label: "Recently played", icon: "󰋚" },
              { type: "tracks", label: "Top songs", icon: "󰎈" },
              { type: "artists", label: "Top artists", icon: "󰠃" },
              { type: "albums", label: "Top albums", icon: "󰀥" }
            ]
            Button {
              required property var modelData
              text: modelData.label
              iconText: modelData.icon
              foreground: panel.foreground
              selected: panel.homeType === modelData.type
              tooltipText: modelData.type === "albums"
                ? "Albums ranked by their songs in your Top songs" : ""
              focusable: false
              hasCursor: panel.cursorOn("page", "home-" + modelData.type)
              onClicked: panel.homeType = modelData.type
              onHovered: function(on) {
                if (on) panel.setPanelCursor("page", "home-" + modelData.type)
              }
              KeyHint { region: "page"; action: "home-" + modelData.type }
            }
          }
        }

        Flow {
          id: gemControls
          width: parent.width
          visible: panel.homeType === "gems"
          spacing: Style.space(5)
          Button {
            text: panel.service ? panel.service.discovery.obscurityLabel : "Obscure · <200,000"
            foreground: panel.foreground
            tooltipText: "Last.fm total listeners: Obscure <200,000; Underground <50,000; Deep underground <10,000. Unknown counts are excluded."
            focusable: false
            hasCursor: panel.cursorOn("page", "gem-obscurity")
            onHovered: function(on) { if (on) panel.setPanelCursor("page", "gem-obscurity") }
            KeyHint { region: "page"; action: "gem-obscurity" }
            onClicked: panel.cycleDiscoverySetting("discoveryObscurity")
          }
          Button {
            text: "Adventure · " + (panel.service ? panel.service.settings.discoveryAdventure : "Balanced")
            foreground: panel.foreground
            tooltipText: "Cycle Close, Balanced, and Adventurous"
            focusable: false
            hasCursor: panel.cursorOn("page", "gem-adventure")
            onHovered: function(on) { if (on) panel.setPanelCursor("page", "gem-adventure") }
            KeyHint { region: "page"; action: "gem-adventure" }
            onClicked: panel.cycleDiscoverySetting("discoveryAdventure")
          }
          Button {
            text: "Refresh gems"
            foreground: panel.foreground
            enabled: panel.service && !panel.service.discovery.loading
            focusable: false
            hasCursor: panel.cursorOn("page", "gem-refresh")
            onHovered: function(on) { if (on) panel.setPanelCursor("page", "gem-refresh") }
            KeyHint { region: "page"; action: "gem-refresh" }
            onClicked: if (panel.service) panel.service.loadHiddenGems(true)
          }
          Button {
            text: "Last.fm settings"
            foreground: panel.foreground
            focusable: false
            hasCursor: panel.cursorOn("page", "gem-settings")
            onHovered: function(on) { if (on) panel.setPanelCursor("page", "gem-settings") }
            KeyHint { region: "page"; action: "gem-settings" }
            onClicked: panel.chooseTab("setup")
          }
        }
        Text {
          id: gemStatus
          width: parent.width
          text: panel.service ? panel.service.discovery.message || panel.service.discovery.warning : ""
          visible: panel.homeType === "gems" && text !== ""
          textFormat: Text.PlainText
          color: panel.muted
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Loader {
          width: parent.width
          height: Math.max(40, parent.height - homeTypes.height - parent.spacing)
          active: panel.homeType === "overview"
          visible: active
          sourceComponent: Component { HomeOverview { controller: homePage.controller } }
        }

        Loader {
          width: parent.width
          height: active ? Math.max(40, parent.height - homeTypes.height - (gemControls.visible ? gemControls.height : 0) - (gemStatus.visible ? gemStatus.height : 0) - parent.spacing * (panel.homeType === "gems" ? 3 : 1)) : 0
          active: panel.homeType !== "overview"
          visible: active
          sourceComponent: Component {
            MediaCollection {
          anchors.fill: parent
          service: panel.service
          onBatchQueueRequested: function(items) { if (panel.service) panel.service.addItemsToQueue(items) }
          onListInteracted: panel.setPanelCursor("page", keyboardListId)
          onBatchPlaylistRequested: function(items) { panel.openPlaylistPicker(items) }
          onBatchSaveRequested: function(items) { if (panel.service) panel.service.toggleSavedItems(items) }
          onBatchRemoveRequested: function(items) { if (panel.service) panel.service.removePlaylistItems(items, actionPlaylist) }
          visible: panel.homeType !== "overview"
          sourceItems: visible && panel.service ? panel.service.homeItems(panel.homeType) : []
          filterText: panel.homeFilter
          showFilter: false
          showQueue: true
          showSave: true
          browseContexts: true
          loading: panel.service && (panel.homeType === "gems"
            ? panel.service.discovery.loading : panel.service.homeLoading)
          hasMore: false
          restoredContentY: panel.scrollFor("home:" + panel.homeType)
          stateKey: "home:" + panel.homeType
          emptyMessage: panel.homeType === "gems"
            ? (panel.service ? panel.service.discovery.setupMessage || panel.service.discovery.message || "Your discoveries will appear here." : "Connect Spotify to find hidden gems.")
            : panel.service && panel.service.homeLoading
            ? "Loading your listening history…"
            : (panel.homeFilter.trim() ? "No matches in " + panel.activeSearchScope.label + "."
              : "No listening history is available yet.")
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
          onViewStateChanged: function(filter, sort, y) {
            panel.rememberScroll("home:" + panel.homeType, y)
          }
        }
          }
        }
      }
    }
