import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

BorderSurface {
  id: root

  required property var itemData
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property bool selected: false
  property bool showPlay: true
  property bool showQueue: false
  property bool showPlaylist: true
  property bool showSave: false
  property bool saved: false
  property bool browseOnActivate: false
  property bool reorderEnabled: false
  property bool reorderDragging: false
  property bool artworkEnabled: true
  property int reorderDropIndicator: 0
  property bool hovered: hoverHandler.hovered
  property bool actionsExpanded: false
  property bool compactRows: false
  property bool albumColumn: false
  property bool dateColumn: false
  property bool selectionEnabled: false
  property var draggedItems: itemData ? [itemData] : []
  property bool externalDragging: false
  readonly property real albumColumnWidth: albumColumn ? Math.min(200, width * 0.2) : 0
  readonly property real dateColumnWidth: dateColumn ? Style.space(96) : 0
  Drag.active: externalDragging
  Drag.source: root
  Drag.keys: ["omarchy-spotify-items"]
  Drag.supportedActions: Qt.CopyAction
  Drag.hotSpot.x: width / 2
  Drag.hotSpot.y: height / 2

  readonly property bool durationActionVisible: itemData
    && itemData.kind === "item" && Number(itemData.durationMs) > 0
  readonly property bool saveActionVisible: showSave && !saved && itemData
    && !!itemData.uri && itemData.type !== "chapter"
  readonly property bool playlistActionVisible: showPlaylist && itemData
    && ["track", "episode"].indexOf(itemData.type) >= 0
  readonly property bool queueActionVisible: showQueue && itemData
    && ["track", "episode"].indexOf(itemData.type) >= 0
  readonly property bool playActionVisible: showPlay && itemData
    && ["show", "audiobook"].indexOf(itemData.type) < 0
  readonly property int fullActionCount: (durationActionVisible ? 1 : 0)
    + (saveActionVisible ? 1 : 0) + (playlistActionVisible ? 1 : 0)
    + (queueActionVisible ? 1 : 0) + (playActionVisible ? 1 : 0)
  // Keep overflow measurements stable without constructing hidden action controls.
  TextMetrics {
    id: toggleMetrics
    text: actionToggle.iconText
    font.family: actionToggle.fontFamily
    font.pixelSize: actionToggle.iconSize
  }
  readonly property real actionButtonInsets: actionToggle.implicitWidth - toggleMetrics.advanceWidth
  component RowAction: Loader {
    id: action
    required property string glyph
    property string tip: ""
    property color foreground: root.foreground
    property color accent: Color.accent
    readonly property real fullWidth: metrics.advanceWidth + root.actionButtonInsets
    signal triggered()
    active: visible
    width: fullWidth
    height: item ? item.implicitHeight : 0
    TextMetrics {
      id: metrics
      text: action.glyph
      font.family: actionToggle.fontFamily
      font.pixelSize: actionToggle.iconSize
    }
    sourceComponent: Button {
      iconText: action.glyph
      tooltipText: action.tip
      foreground: action.foreground
      accent: action.accent
      horizontalPadding: Style.space(7)
      onClicked: action.triggered()
    }
  }
  readonly property real fullActionWidth:
    (durationActionVisible ? durationLabel.implicitWidth : 0)
    + (saveActionVisible ? saveButton.fullWidth : 0)
    + (playlistActionVisible ? playlistButton.fullWidth : 0)
    + (queueActionVisible ? queueButton.fullWidth : 0)
    + (playActionVisible ? playButton.fullWidth : 0)
    + Math.max(0, fullActionCount - 1) * Style.space(2)
  readonly property real titleWidthWithFullActions: Math.max(0,
    contentRow.width - artworkSurface.width - fullActionWidth
      - albumColumnWidth - dateColumnWidth
      - contentRow.spacing * (artworkSurface.visible ? 2 : 1))
  readonly property bool compactActions: Api.mediaRowShouldCompact(
    titleMetrics.advanceWidth, titleWidthWithFullActions, fullActionCount)

  signal activated(var item)
  signal openRequested(var item)
  signal queueRequested(var item)
  signal playlistRequested(var item)
  signal saveRequested(var item)
  signal artistRequested(var item)
  signal albumRequested(var item)
  signal contextRequested(var item, real sceneX, real sceneY)
  signal reorderDragStarted(real sceneY)
  signal reorderDragMoved(real sceneY)
  signal reorderDragFinished(real sceneY)
  signal reorderDragCanceled()
  signal selectionRequested(int modifiers)

  function triggerPrimary() {
    if (browseOnActivate) openRequested(itemData)
    else activated(itemData)
  }

  function triggerPlay() { activated(itemData) }

  onItemDataChanged: actionsExpanded = false
  onCompactActionsChanged: if (!compactActions) actionsExpanded = false

  width: parent ? parent.width : implicitWidth
  implicitWidth: Style.space(420)
  implicitHeight: (root.artworkEnabled && !compactRows ? Style.space(66) : Style.space(44))
    + (root.itemData && root.itemData.discoveryReason ? Style.space(20) : 0)
  height: implicitHeight
  radius: Style.cornerRadius
  color: selected || reorderDragging
    ? Style.selectedFillFor(foreground, accent)
    : (reorderDropIndicator !== 0 ? Style.hoverFillFor(foreground, accent)
    : (hovered ? Style.hoverFillFor(foreground, accent) : "transparent"))
  borderSpec: selected || reorderDragging
    ? Border.controlSpec("selected", foreground, accent)
    : Border.none()
  opacity: reorderDragging ? 0.55 : 1
  clip: true

  HoverHandler { id: hoverHandler }

  TextMetrics {
    id: titleMetrics
    text: root.itemData ? String(root.itemData.name || "Untitled") : "Untitled"
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: root.selected
  }

  MouseArea {
    id: rowMouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: root.reorderEnabled || externalCandidate
    cursorShape: root.reorderEnabled
      ? (reorderGesture ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
      : Qt.PointingHandCursor

    property bool reorderCandidate: false
    property bool reorderGesture: false
    property bool suppressActivation: false
    property real pressSceneY: 0
    property real pressX: 0
    property bool externalCandidate: false

    function pointerSceneY(mouse) {
      return mapToItem(null, mouse.x, mouse.y).y
    }

    onPressed: function(mouse) {
      suppressActivation = false
      reorderCandidate = mouse.button === Qt.LeftButton && root.reorderEnabled
      externalCandidate = mouse.button === Qt.LeftButton && root.selectionEnabled
        && (mouse.modifiers & Qt.ControlModifier) !== 0
      reorderGesture = false
      if (reorderCandidate || externalCandidate) {
        pressSceneY = pointerSceneY(mouse)
        pressX = mouse.x
      }
    }

    onPositionChanged: function(mouse) {
      if ((!reorderCandidate && !externalCandidate) || !pressed) return
      var sceneY = pointerSceneY(mouse)
      if (externalCandidate && (root.externalDragging
          || Math.abs(sceneY - pressSceneY) + Math.abs(mouse.x - pressX) >= Style.space(6))) {
        suppressActivation = true
        root.externalDragging = true
        root.Drag.hotSpot.x = mouse.x
        root.Drag.hotSpot.y = mouse.y
        return
      }
      if (!reorderGesture
          && Math.abs(sceneY - pressSceneY) >= Style.space(6)) {
        reorderGesture = true
        suppressActivation = true
        root.reorderDragStarted(pressSceneY)
      }
      if (reorderGesture) root.reorderDragMoved(sceneY)
    }

    onReleased: function(mouse) {
      if (root.externalDragging) root.Drag.drop()
      root.externalDragging = false
      externalCandidate = false
      if (reorderGesture) root.reorderDragFinished(pointerSceneY(mouse))
      reorderCandidate = false
      reorderGesture = false
    }

    onCanceled: {
      if (reorderGesture) root.reorderDragCanceled()
      reorderCandidate = false
      reorderGesture = false
      suppressActivation = false
      externalCandidate = false
      root.externalDragging = false
    }

    onClicked: function(mouse) {
      if (suppressActivation) {
        suppressActivation = false
        return
      }
      if (mouse.button === Qt.RightButton) {
        var scenePoint = root.mapToItem(null, mouse.x, mouse.y)
        root.contextRequested(root.itemData, scenePoint.x, scenePoint.y)
      } else {
        if (root.selectionEnabled) root.selectionRequested(mouse.modifiers)
        else root.triggerPrimary()
      }
    }
    onDoubleClicked: function(mouse) {
      if (root.selectionEnabled && mouse.modifiers === Qt.NoModifier) root.triggerPrimary()
    }
  }

  Row {
    id: contentRow
    anchors.fill: parent
    anchors.margins: Style.space(6)
    spacing: Style.space(9)

    BorderSurface {
      id: artworkSurface
      width: root.artworkEnabled ? parent.height : 0
      height: width
      visible: root.artworkEnabled
      radius: Style.spacing.labelGap
      color: Style.normalFillFor(root.foreground, root.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

      RetryImage {
        id: rowArtwork
        anchors.fill: parent
        anchors.margins: Style.space(2)
        requestedSource: root.artworkEnabled && root.itemData && root.itemData.imageUrl
          ? root.itemData.imageUrl : ""
        retryLimit: 4
        sourceSize.width: 112
        sourceSize.height: 112
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        // List delegates are recycled; do not retain every scrolled artwork
        // pixmap in the process. The current-track artwork is the only image
        // intentionally kept in Qt's shared cache.
        cache: false
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: rowArtwork.status !== Image.Ready
        text: !root.itemData ? "󰝚"
          : (root.itemData.type === "playlist" ? "󰲸"
          : (root.itemData.type === "artist" ? "󰠃"
          : (root.itemData.type === "album" ? "󰀥"
          : (root.itemData.type === "show" || root.itemData.type === "episode" ? "󰦔"
          : (root.itemData.type === "audiobook" || root.itemData.type === "chapter" ? "󰂺" : "󰝚")))))
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge
      }
    }

    Column {
      width: Math.max(20, parent.width - artworkSurface.width - actionRow.width
        - root.albumColumnWidth - root.dateColumnWidth
        - parent.spacing * ((artworkSurface.visible ? 2 : 1)
          + (root.albumColumn ? 1 : 0) + (root.dateColumn ? 1 : 0)))
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        id: titleText
        objectName: "media-row-title"
        width: parent.width
        text: root.itemData ? String(root.itemData.name || "Untitled") : "Untitled"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.selected
        elide: Text.ElideRight
      }

      MediaByline {
        width: parent.width
        itemData: root.itemData
        foreground: root.foreground
        muted: root.muted
        accent: root.accent
        albumColor: root.accent
        fontFamily: root.fontFamily
        fontPixelSize: Style.font.bodySmall
        onArtistRequested: function(item) { root.artistRequested(item) }
        onAlbumRequested: function(item) { root.albumRequested(item) }
        onContextRequested: function(item) { root.openRequested(item) }
      }
      Text {
        width: parent.width
        visible: !!root.itemData && !!root.itemData.discoveryReason
        text: root.itemData ? String(root.itemData.discoveryReason || "") : ""
        textFormat: Text.PlainText
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      width: root.albumColumnWidth
      visible: root.albumColumn
      anchors.verticalCenter: parent.verticalCenter
      text: root.itemData ? String(root.itemData.album || "") : ""
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
    Text {
      width: root.dateColumnWidth
      visible: root.dateColumn
      anchors.verticalCenter: parent.verticalCenter
      text: root.itemData ? String(root.itemData.addedAt || root.itemData.playedAt || "").slice(0, 10) : ""
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Row {
      id: actionRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        id: durationLabel
        objectName: "media-row-duration"
        visible: root.durationActionVisible
          && (root.compactRows || !root.compactActions || root.actionsExpanded)
        anchors.verticalCenter: parent.verticalCenter
        text: Api.millisecondsToClock(root.itemData ? root.itemData.durationMs : 0)
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      RowAction {
        id: saveButton
        objectName: "media-row-save"
        visible: root.saveActionVisible
        glyph: "󰋑"
        foreground: Color.urgent
        accent: Color.urgent
        tip: "Save to library"
        onTriggered: root.saveRequested(root.itemData)
      }

      RowAction {
        id: playlistButton
        objectName: "media-row-playlist"
        visible: root.playlistActionVisible
          && (!root.compactActions || root.actionsExpanded)
        glyph: "󱁐"
        foreground: root.foreground
        tip: "Add to playlist"
        onTriggered: root.playlistRequested(root.itemData)
      }

      RowAction {
        id: queueButton
        objectName: "media-row-queue"
        visible: root.queueActionVisible
          && (!root.compactActions || root.actionsExpanded)
        glyph: "󰐕"
        foreground: root.foreground
        tip: "Add to queue"
        onTriggered: root.queueRequested(root.itemData)
      }

      RowAction {
        id: playButton
        objectName: "media-row-play"
        visible: root.playActionVisible
          && (!root.compactActions || root.actionsExpanded)
        glyph: "󰐊"
        foreground: root.foreground
        tip: "Play"
        onTriggered: root.triggerPlay()
      }

      Button {
        id: actionToggle
        objectName: "media-row-actions-toggle"
        visible: root.compactActions
        iconText: root.actionsExpanded ? "󰅖" : "󰇙"
        foreground: root.foreground
        tooltipText: root.actionsExpanded
          ? "Hide row actions" : "Show duration and actions"
        horizontalPadding: Style.space(7)
        onClicked: root.actionsExpanded = !root.actionsExpanded
      }

    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(2, Style.space(2))
    y: root.reorderDropIndicator < 0 ? 0 : parent.height - height
    visible: root.reorderDropIndicator !== 0
    color: root.accent
    z: 5
  }
}
