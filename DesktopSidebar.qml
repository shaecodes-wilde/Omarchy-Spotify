import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: sidebar
  required property var controller
  readonly property var panel: controller
  readonly property bool collapsed: panel.compactWidth || panel.sidebarCollapsed
  property alias playlistList: playlistShortcuts
  component KeyHint: DesktopKeyHint { controller: sidebar.controller }
            visible: panel.currentTab !== "login" && !panel.extraNarrowWidth
            width: visible
              ? (sidebar.collapsed ? Style.space(54)
                : Math.min(Style.space(panel.sidebarWidth), parent.width * 0.4))
              : 0
            height: parent.height
            radius: Style.cornerRadius
            color: Style.normalFillFor(panel.foreground, panel.accent)
            borderSpec: Border.controlSpec("normal", panel.foreground, panel.accent)

            Row {
              id: brandRow
              visible: !panel.compactHeight
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: visible ? Style.space(11) : 0
              height: visible ? Style.space(42) : 0
              spacing: Style.space(9)

              OpticalGlyph {
                width: sidebar.collapsed ? parent.width : Style.space(18)
                height: parent.height
                text: ""
                color: panel.accent
                fontFamily: panel.fontFamily
                fontSize: Style.font.iconLarge
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panel.sidebarCollapsed = !panel.sidebarCollapsed
                }
              }

              Column {
                visible: !sidebar.collapsed
                width: Math.max(40, parent.width - Style.space(38))
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  width: parent.width
                  text: "Music"
                  color: panel.foreground
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: "for Spotify"
                  color: panel.muted
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            Column {
              id: primaryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: brandRow.visible ? brandRow.bottom : parent.top
              anchors.margins: Style.space(8)
              spacing: Style.space(2)

              PanelSeparator {
                width: parent.width
                foreground: panel.foreground
              }

              Repeater {
                model: panel.primaryNavigationItems()

                Button {
                  required property var modelData
                  readonly property bool radioEntry: modelData.id === "radio"
                  width: primaryNavigation.width
                  text: sidebar.collapsed ? "" : modelData.label
                  iconText: sidebar.collapsed ? "" : modelData.icon
                  foreground: panel.foreground
                  selected: radioEntry ? panel.radioNavigationSelected()
                    : panel.currentTab === modelData.id
                  leftAlign: !sidebar.collapsed
                  horizontalPadding: sidebar.collapsed
                    ? 0 : Style.spacing.controlPaddingX
                  focusable: false
                  hasCursor: panel.cursorOn("sidebar", "nav-" + modelData.id)
                  tooltipText: radioEntry && panel.service && panel.service.lastRadioPlaylist
                    ? modelData.label + " · " + panel.service.lastRadioPlaylist.name
                    : panel.shortcutHint(modelData.label,
                      panel.primaryNavigationShortcut(modelData.id))
                  onClicked: {
                    if (radioEntry) panel.openLastRadio()
                    else panel.chooseTab(modelData.id)
                  }
                  onHovered: function(on) {
                    if (on) panel.setPanelCursor("sidebar", "nav-" + modelData.id)
                  }
                  KeyHint {
                    region: "sidebar"
                    action: "nav-" + modelData.id
                    sequences: panel.primaryNavigationShortcut(modelData.id)
                  }
                  OpticalGlyph {
                    anchors.fill: parent
                    visible: sidebar.collapsed
                    text: modelData.icon
                    color: parent.selected
                      ? Style.selectedStateColor(panel.foreground, panel.accent)
                      : panel.foreground
                    fontFamily: panel.fontFamily
                    fontSize: Style.font.icon
                  }
                }
              }

              PanelSeparator {
                width: parent.width
                foreground: panel.foreground
              }
            }

            Text {
              id: playlistShortcutsHeading
              visible: !sidebar.collapsed
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: primaryNavigation.bottom
              anchors.leftMargin: Style.space(13)
              anchors.rightMargin: Style.space(13)
              anchors.topMargin: Style.space(9)
              height: visible ? implicitHeight : 0
              text: "YOUR LIBRARY"
              color: panel.muted
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Column {
              id: libraryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: playlistShortcutsHeading.visible
                ? playlistShortcutsHeading.bottom : primaryNavigation.bottom
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              anchors.topMargin: Style.space(6)
              spacing: Style.space(2)

              Button {
                width: parent.width
                text: sidebar.collapsed ? "" : "Liked Songs"
                iconText: sidebar.collapsed ? "" : "󰋑"
                foreground: panel.foreground
                selected: panel.currentTab === "library"
                leftAlign: !sidebar.collapsed
                horizontalPadding: sidebar.collapsed
                  ? 0 : Style.spacing.controlPaddingX
                focusable: false
                hasCursor: panel.cursorOn("sidebar", "nav-library")
                tooltipText: "Liked Songs"
                onClicked: panel.chooseTab("library")
                onHovered: function(on) {
                  if (on) panel.setPanelCursor("sidebar", "nav-library")
                }
                KeyHint { region: "sidebar"; action: "nav-library" }
                OpticalGlyph {
                  anchors.fill: parent
                  visible: sidebar.collapsed
                  text: "󰋑"
                  color: parent.selected
                    ? Style.selectedStateColor(panel.foreground, panel.accent)
                    : panel.foreground
                  fontFamily: panel.fontFamily
                  fontSize: Style.font.icon
                }
              }

              Grid {
                width: parent.width
                columns: sidebar.collapsed ? 1 : 2
                spacing: Style.space(2)

                Button {
                  width: sidebar.collapsed ? parent.width
                    : Math.max(20, parent.width - createPlaylistShortcut.width
                      - parent.spacing)
                  text: sidebar.collapsed ? "" : "Playlists"
                  iconText: sidebar.collapsed ? "" : "󱁐"
                  foreground: panel.foreground
                  selected: panel.currentTab === "playlists"
                  leftAlign: !sidebar.collapsed
                  horizontalPadding: sidebar.collapsed
                    ? 0 : Style.spacing.controlPaddingX
                  focusable: false
                  hasCursor: panel.cursorOn("sidebar", "nav-playlists")
                  tooltipText: "Playlists"
                  onClicked: panel.chooseTab("playlists")
                  onHovered: function(on) {
                    if (on) panel.setPanelCursor("sidebar", "nav-playlists")
                  }
                  KeyHint { region: "sidebar"; action: "nav-playlists" }
                  OpticalGlyph {
                    anchors.fill: parent
                    visible: sidebar.collapsed
                    text: "󱁐"
                    color: parent.selected
                      ? Style.selectedStateColor(panel.foreground, panel.accent)
                      : panel.foreground
                    fontFamily: panel.fontFamily
                    fontSize: Style.font.icon
                  }
                }

                Button {
                  id: createPlaylistShortcut
                  width: sidebar.collapsed
                    ? parent.width : implicitWidth
                  text: "+"
                  foreground: panel.foreground
                  fontSize: Style.font.subtitle
                  horizontalPadding: Style.space(7)
                  focusable: false
                  hasCursor: panel.cursorOn("sidebar", "nav-create")
                  tooltipText: "Create a new playlist"
                  enabled: panel.accountConnected && panel.service
                    && !panel.service.playlistActionBusy
                  onClicked: panel.openCreatePlaylistPopup()
                  onHovered: function(on) {
                    if (on) panel.setPanelCursor("sidebar", "nav-create")
                  }
                  KeyHint { region: "sidebar"; action: "nav-create" }
                }
              }
            }

            ListView {
              id: playlistShortcuts
              visible: !sidebar.collapsed
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: libraryNavigation.bottom
              anchors.bottom: setupNavButton.top
              anchors.margins: Style.space(8)
              model: panel.sidebarItems()
              clip: true
              spacing: Style.space(1)
              reuseItems: true
              keyNavigationEnabled: false
              highlightFollowsCurrentItem: true

              FastScrollHandler {
                parent: playlistShortcuts
                flickable: playlistShortcuts
                onScrolled: {
                  if (playlistShortcuts.atYEnd && panel.service
                      && panel.service.playlistsNext
                      && !panel.service.playlistsLoading)
                    panel.service.loadMorePlaylists()
                }
              }

              onMovementEnded: {
                if (atYEnd && panel.service && panel.service.playlistsNext
                    && !panel.service.playlistsLoading) panel.service.loadMorePlaylists()
              }

              delegate: Button {
                required property var modelData
                required property int index
                width: ListView.view.width
                text: panel.sidebarPlaylistName(modelData)
                iconText: panel.playlistPins.indexOf(modelData.id) >= 0 ? "󰐃" : "󰲸"
                foreground: panel.foreground
                leftAlign: true
                focusable: false
                hasCursor: panel.cursorOn("sidebar", "sidebar-playlists")
                  && ListView.isCurrentItem
                selected: panel.currentTab === "playlists" && panel.service
                  && panel.service.selectedPlaylist
                  && panel.service.selectedPlaylist.id === modelData.id
                DropArea {
                  anchors.fill: parent
                  keys: ["omarchy-spotify-items"]
                  enabled: panel.service && panel.service.playlistEditable(modelData)
                    && !panel.service.playlistActionBusy
                  onDropped: function(drop) {
                    var items = drop.source ? drop.source.draggedItems : []
                    if (items && items.length) {
                      panel.service.addItemsToPlaylist(items, modelData)
                      drop.acceptProposedAction()
                    }
                  }
                }
                tooltipText: (modelData.name || "Playlist") + " · Right-click to "
                  + (panel.playlistPins.indexOf(modelData.id) >= 0 ? "unpin" : "pin locally")
                onRightClicked: panel.togglePlaylistPin(modelData)
                onClicked: {
                  panel.openPlaylist(modelData)
                }
                onHovered: function(on) {
                  if (!on) return
                  playlistShortcuts.currentIndex = index
                  panel.setPanelCursor("sidebar", "sidebar-playlists")
                }
                KeyHint {
                  active: panel.shortcutHintsActive
                  navHint: {
                    playlistShortcuts.currentIndex
                    playlistShortcuts.contentY
                    panel.panelCursorAction
                    panel.panelCursorRegion
                    panel.hintCtrlHeld
                    panel.hintShiftHeld
                    panel.hintAltHeld
                    return panel.sidebarPlaylistNavHint(index)
                  }
                }
              }
            }

            Button {
              id: setupNavButton
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(8)
              text: sidebar.collapsed ? "" : "Settings"
              iconText: sidebar.collapsed ? ""
                : (panel.service && panel.service.auth.loggedIn ? "󰀄" : "󰒓")
              foreground: panel.foreground
              selected: panel.currentTab === "setup"
              leftAlign: !sidebar.collapsed
              focusable: false
              hasCursor: panel.cursorOn("sidebar", "nav-settings")
              tooltipText: panel.shortcutHint("Settings", "Ctrl+,")
              KeyHint { region: "sidebar"; action: "nav-settings"; sequences: ["Ctrl+,"] }
              onClicked: panel.chooseTab("setup")
              onHovered: function(on) {
                if (on) panel.setPanelCursor("sidebar", "nav-settings")
              }
              OpticalGlyph {
                anchors.fill: parent
                visible: sidebar.collapsed
                text: panel.service && panel.service.auth.loggedIn ? "󰀄" : "󰒓"
                color: parent.selected
                  ? Style.selectedStateColor(panel.foreground, panel.accent)
                  : panel.foreground
                fontFamily: panel.fontFamily
                fontSize: Style.font.icon
              }
            }
          
  MouseArea {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(7)
    enabled: !sidebar.collapsed
    cursorShape: Qt.SizeHorCursor
    property real startX: 0
    property real startWidth: 0
    onPressed: function(mouse) {
      startX = mapToGlobal(mouse.x, mouse.y).x
      startWidth = panel.sidebarWidth
    }
    onPositionChanged: function(mouse) {
      if (pressed) panel.sidebarWidth = Math.max(176, Math.min(360,
        startWidth + (mapToGlobal(mouse.x, mouse.y).x - startX) / Style.space(1)))
    }
  }
}
