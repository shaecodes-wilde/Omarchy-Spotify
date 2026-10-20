import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

import "Api.js" as Api
import "Selection.js" as Selection

Item {
  id: root
  objectName: "media-collection"
  property var navigationOwner: null

  required property var service
  property var sourceItems: []
  property string filterText: ""
  property string sortKey: "default"
  property string contextUri: ""
  property bool showFilter: true
  property bool showSort: showFilter
  property bool showQueue: true
  property bool showPlaylist: true
  property bool showSave: true
  property bool browseContexts: true
  property bool loading: false
  property bool hasMore: false
  property string emptyMessage: "Nothing here yet."
  property real restoredContentY: 0
  property string stateKey: ""
  property bool restoreReady: true
  property bool restoreApplied: false
  property bool keyboardSortSelected: false
  property bool keyboardMoreSelected: false
  property bool keyboardFilterScanSelected: false
  property string keyboardFilterScanHint: ""
  property string keyboardSortHint: ""
  property string keyboardMoreHint: ""
  property string keyboardListHint: ""
  property bool keyboardAtList: false
  property bool keyboardAtListPrev: false
  property bool keyboardAtListNext: false
  property bool keyboardListIsTab: false
  property bool keyboardListIsBacktab: false
  property bool keyboardNavModifiers: false
  property bool keyboardCtrlHeld: false
  property bool keyboardShiftHeld: false
  property bool keyboardAltHeld: false
  property bool keyboardHintsActive: false
  property string keyboardListId: "list"
  readonly property int listCurrentIndex: mediaList.currentIndex
  readonly property int listCount: mediaList.count
  property bool allowReorder: false
  property bool reorderBusy: false
  property int dragSourceIndex: -1
  property int dragDestinationIndex: -1
  property real dragSceneY: 0
  property int dragAutoScrollDirection: 0
  property bool enableSelection: true
  readonly property var actionPlaylist: {
    if (!service || !contextUri) return null
    if (service.selectedPlaylist && service.selectedPlaylist.uri === contextUri) return service.selectedPlaylist
    if (service.detailItem && service.detailItem.type === "playlist" && service.detailItem.uri === contextUri) return service.detailItem
    return null
  }
  property bool allowRemove: !!actionPlaylist && service.playlistEditable(actionPlaylist)
  property bool showTableTools: showSort
  property var selection: ({})
  property int selectionAnchor: -1
  readonly property int selectionCount: Object.keys(selection).length
  readonly property bool trackTable: sourceItems.length > 0 && sourceItems[0].kind === "item"
  readonly property bool compactRows: !service || !service.settings
    || service.settings.trackDensity !== "Comfortable"
  readonly property string columns: service && service.settings
    ? String(service.settings.trackColumns || "Album + date") : "Album + date"
  readonly property bool albumColumn: trackTable && width >= Style.space(600) && columns !== "Title only"
  readonly property bool dateColumn: albumColumn && width >= Style.space(850) && columns === "Album + date"

  readonly property var visibleItems: Api.filteredSorted(sourceItems, filterText, sortKey)
  readonly property bool playbackUsesVisibleOrder: Api.playbackUsesVisibleOrder(
    contextUri, filterText, sortKey)
  readonly property string playbackContextUri: Api.playbackContextForView(
    contextUri, filterText, sortKey)
  readonly property var sortKeys: ["default", "name", "artist", "album", "duration",
    "date", "date-asc"]
  readonly property bool canReorder: allowReorder && !reorderBusy
    && String(filterText || "").trim() === "" && sortKey === "default"
    && visibleItems.length > 1
  readonly property var dragItem: dragSourceIndex >= 0
    && dragSourceIndex < visibleItems.length ? visibleItems[dragSourceIndex] : null

  signal activated(var item, var sourceItems, string contextUri)
  signal opened(var item)
  signal queued(var item)
  signal playlistRequested(var item)
  signal saveToggled(var item)
  signal contextRequested(var item, real sceneX, real sceneY, int index,
    var sourceItems, string contextUri, string playbackContextUri)
  signal reorderRequested(int sourceIndex, int destinationIndex)
  signal loadMoreRequested()
  signal viewStateChanged(string filterText, string sortKey, real contentY)
  signal batchQueueRequested(var items)
  signal batchPlaylistRequested(var items)
  signal batchSaveRequested(var items)
  signal batchRemoveRequested(var items)
  signal listInteracted()
  readonly property var selectedRows: selectionCount ? Selection.items(sourceItems, selection) : []

  function selectedItems() { return selectedRows }
  function isSelected(item) {
    if (selectionCount === 0) return false
    return selection[Selection.key(item)] === true
  }
  function clearSelection() { selection = ({}); selectionAnchor = -1 }
  function restoreCurrentIndex(index) {
    mediaList.currentIndex = Math.min(mediaList.count - 1, Math.max(0, Math.floor(Number(index) || 0)))
  }
  function selectRow(index, modifiers) {
    selection = Selection.select(visibleItems, selection, index,
      selectionAnchor, (modifiers & Qt.ControlModifier) !== 0,
      (modifiers & Qt.ShiftModifier) !== 0)
    if ((modifiers & Qt.ShiftModifier) === 0 || selectionAnchor < 0) selectionAnchor = index
    mediaList.currentIndex = index
    listInteracted()
    mediaList.forceActiveFocus()
  }
  function selectAll() {
    selection = Selection.select(visibleItems, ({}), visibleItems.length - 1, 0, false, true)
  }
  function setSort(value) {
    sortKey = value
    viewStateChanged(filterText, sortKey, mediaList.contentY)
  }
  function cycleColumns() {
    var values = ["Album + date", "Album", "Title only"]
    if (service) service.persistSettings({ trackColumns: values[(values.indexOf(columns) + 1) % values.length] })
  }

  readonly property bool filterScanAvailable: scanner.available
  readonly property bool filterScanPaused: scanner.paused
  function continueFilterScan() { scanner.resume() }
  function cancelFilterScan() { scanner.cancel() }
  FilterScanController {
    id: scanner
    query: root.filterText
    active: root.visible && root.service && root.service.uiVisible
    loading: root.loading
    hasMore: root.hasMore
    itemCount: root.sourceItems.length
    cooldownUntil: root.service ? root.service.searchCooldownUntil : 0
    blocked: !root.service || !root.service.accountConnected
      || root.service.lastError !== ""
    onRequestNext: root.loadMoreRequested()
  }

  function sortLabel() {
    if (sortKey === "name") return "Title"
    if (sortKey === "artist") return "Artist"
    if (sortKey === "album") return "Album"
    if (sortKey === "duration") return "Duration"
    if (sortKey === "date") return "Date: newest"
    if (sortKey === "date-asc") return "Date: oldest"
    return "Original"
  }

  function cycleSort() {
    var index = sortKeys.indexOf(sortKey)
    sortKey = sortKeys[(index + 1) % sortKeys.length]
    viewStateChanged(filterText, sortKey, mediaList.contentY)
  }

  function focusList() {
    mediaList.forceActiveFocus()
    if (mediaList.currentIndex < 0 && mediaList.count > 0) mediaList.currentIndex = 0
  }

  function moveCurrent(delta) {
    var next = Api.listIndexAfterMove(mediaList.count, mediaList.currentIndex, delta)
    if (next < 0) return false
    mediaList.currentIndex = next
    if (keyboardShiftHeld) selectRow(next, Qt.ShiftModifier)
    return true
  }

  function currentContextAnchor() {
    var index = mediaList.currentIndex
    if (index < 0 || index >= visibleItems.length) return null
    var row = mediaList.currentItem
    var point = row ? row.mapToItem(null, row.width / 2, row.height / 2)
      : ({ x: 0, y: 0 })
    return {
      item: visibleItems[index],
      index: index,
      x: point.x,
      y: point.y,
      items: visibleItems,
      uri: contextUri,
      playbackUri: playbackContextUri
    }
  }

  function activateCurrent() {
    if (mediaList.currentItem) mediaList.currentItem.triggerPrimary()
  }

  function jumpToEdge(toEnd) {
    if (mediaList.count <= 0) return
    mediaList.currentIndex = toEnd ? mediaList.count - 1 : 0
  }

  function firstVisibleListIndex() {
    if (mediaList.count <= 0) return 0
    var y = mediaList.contentY + 1
    if (y < mediaList.originY) y = mediaList.originY + 1
    var index = mediaList.indexAt(Math.max(1, mediaList.width / 2), y)
    return Api.listHintRowIndex(mediaList.count, index)
  }

  function jumpToFirstVisible() {
    if (mediaList.count <= 0) return
    mediaList.currentIndex = firstVisibleListIndex()
  }

  function blurList() {
    mediaList.focus = false
  }

  function rowNavHint(index) {
    if (!keyboardHintsActive) return ""
    return Api.cursorListRowHint({
      rowIndex: index,
      currentIndex: mediaList.currentIndex,
      count: mediaList.count,
      tabRowIndex: firstVisibleListIndex(),
      atList: keyboardAtList,
      previousIsCurrent: keyboardAtListPrev,
      nextIsCurrent: keyboardAtListNext,
      tabIsList: keyboardListIsTab,
      backtabIsList: keyboardListIsBacktab,
      modifiersHeld: keyboardNavModifiers
    })
  }

  function requestMore() {
    if (hasMore && !loading) loadMoreRequested()
  }

  function reorderIndexAtSceneY(sceneY) {
    if (mediaList.count <= 0) return -1
    var top = mediaList.mapToItem(null, 0, 0)
    var bottom = mediaList.mapToItem(null, 0, mediaList.height)
    var center = mediaList.mapToItem(null, mediaList.width / 2, 0)
    var clampedY = Math.max(top.y + 1, Math.min(bottom.y - 1, sceneY))
    var contentPoint = mediaList.contentItem.mapFromItem(null, center.x, clampedY)
    var candidate = mediaList.indexAt(contentPoint.x, contentPoint.y)
    if (candidate >= 0) return candidate

    // The pointer can land in ListView.spacing, where indexAt() intentionally
    // returns -1. Pick the nearest instantiated row in that case.
    var closest = -1
    var closestDistance = Number.MAX_VALUE
    for (var i = 0; i < mediaList.count; i++) {
      var row = mediaList.itemAtIndex(i)
      if (!row) continue
      var rowCenter = row.mapToItem(null, row.width / 2, row.height / 2)
      var distance = Math.abs(rowCenter.y - clampedY)
      if (distance < closestDistance) {
        closest = i
        closestDistance = distance
      }
    }
    if (closest >= 0) return closest
    return contentPoint.y <= mediaList.originY ? 0 : mediaList.count - 1
  }

  function updateReorder(sceneY) {
    if (dragSourceIndex < 0) return
    dragSceneY = sceneY
    dragDestinationIndex = reorderIndexAtSceneY(sceneY)
    var center = mediaList.mapToItem(null, mediaList.width / 2, 0)
    var point = mediaList.mapFromItem(null, center.x, sceneY)
    var edge = Math.min(Style.space(48), mediaList.height / 3)
    dragAutoScrollDirection = point.y < edge ? -1
      : (point.y > mediaList.height - edge ? 1 : 0)
  }

  function beginReorder(index, sceneY) {
    if (!canReorder || index < 0 || index >= visibleItems.length) return
    mediaList.cancelFlick()
    dragSourceIndex = index
    dragDestinationIndex = index
    dragSceneY = sceneY
    dragAutoScrollDirection = 0
  }

  function finishReorder(sceneY, canceled) {
    if (dragSourceIndex < 0) return
    if (!canceled) updateReorder(sceneY)
    var source = dragSourceIndex
    var destination = dragDestinationIndex
    dragSourceIndex = -1
    dragDestinationIndex = -1
    dragAutoScrollDirection = 0
    rememberView()
    if (!canceled && destination >= 0 && destination !== source)
      reorderRequested(source, destination)
  }

  function cancelReorder() {
    finishReorder(dragSceneY, true)
  }

  function rememberView() {
    viewStateChanged(filterText, sortKey, mediaList.contentY)
  }

  function restoreView() {
    if (!restoreReady || restoreApplied || restoredContentY <= 0
        || mediaList.count <= 0) return
    restoreTimer.restart()
  }

  function resetRestore() {
    restoreApplied = false
    if (restoreReady) restoreTimer.restart()
  }

  Timer {
    id: restoreTimer
    interval: 0
    onTriggered: {
      if (!root.restoreReady || root.restoreApplied) return
      if (root.restoredContentY <= 0) {
        mediaList.contentY = mediaList.originY
        root.restoreApplied = true
        return
      }
      if (mediaList.count <= 0) return
      var maximum = Math.max(mediaList.originY,
        mediaList.contentHeight - mediaList.height + mediaList.originY)
      mediaList.contentY = Math.max(mediaList.originY,
        Math.min(maximum, root.restoredContentY))
      root.restoreApplied = true
    }
  }

  Component.onCompleted: {
    restoreView()
    if (navigationOwner) navigationOwner.registerCollection(root)
  }
  onSourceItemsChanged: {
    if (selectionCount > 0) selection = Selection.retain(sourceItems, selection)
    if (selectionCount === 0) selectionAnchor = -1
  }
  onFilterTextChanged: clearSelection()
  onSortKeyChanged: clearSelection()
  onRestoredContentYChanged: resetRestore()
  onStateKeyChanged: resetRestore()
  onRestoreReadyChanged: if (restoreReady) resetRestore()
  onCanReorderChanged: if (!canReorder) cancelReorder()
  Component.onDestruction: {
    if (navigationOwner) navigationOwner.unregisterCollection(root)
    rememberView()
  }

  Timer {
    interval: 30
    repeat: true
    running: root.dragSourceIndex >= 0 && root.dragAutoScrollDirection !== 0
    onTriggered: {
      var minimum = mediaList.originY
      var maximum = Math.max(minimum,
        mediaList.contentHeight - mediaList.height + mediaList.originY)
      var next = Math.max(minimum, Math.min(maximum,
        mediaList.contentY + root.dragAutoScrollDirection * Style.space(9)))
      if (next === mediaList.contentY) return
      mediaList.contentY = next
      root.updateReorder(root.dragSceneY)
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(7)

    Row {
      id: tools
      width: parent.width
      height: visible ? Style.space(38) : 0
      visible: root.showFilter || root.showSort
      spacing: Style.space(7)

      TextField {
        id: filterField
        visible: root.showFilter
        width: visible ? Math.max(80, parent.width
          - (sortButton.visible ? sortButton.width + parent.spacing : 0)
          - countLabel.width - parent.spacing) : 0
        foreground: Color.foreground
        placeholderText: "Filter this list"
        text: root.filterText
        onTextEdited: {
          root.filterText = text
          root.viewStateChanged(root.filterText, root.sortKey, mediaList.contentY)
        }
        Keys.onDownPressed: root.focusList()
      }

      Button {
        id: sortButton
        visible: root.showSort
        text: root.sortLabel()
        iconText: "󰒺"
        foreground: Color.foreground
        tooltipText: "Change sort order"
        focusable: false
        hasCursor: root.keyboardSortSelected
        onClicked: root.cycleSort()
        ShortcutHint {
          active: root.keyboardHintsActive && root.keyboardSortHint !== ""
          navHint: root.keyboardSortHint
        }
      }

      Text {
        id: countLabel
        anchors.verticalCenter: parent.verticalCenter
        text: root.visibleItems.length
          + (root.filterText ? (root.visibleItems.length === 1 ? " match" : " matches")
            : (root.visibleItems.length === 1 ? " item" : " items"))
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Loader {
      id: selectionTools
      objectName: "media-selection-tools"
      width: parent.width
      active: root.selectionCount > 0
      visible: active
      height: active && item ? item.implicitHeight : 0
      sourceComponent: Component {
        Flow {
          width: selectionTools.width
          spacing: Style.space(5)
          Text {
            text: root.selectionCount + " selected"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Button { visible: root.showQueue; text: "Queue"; onClicked: root.batchQueueRequested(root.selectedItems()) }
          Button { visible: root.showPlaylist; text: "Add to playlist…"; onClicked: root.batchPlaylistRequested(root.selectedItems()) }
          Button { visible: root.showSave; text: "Save / unsave"; onClicked: root.batchSaveRequested(root.selectedItems()) }
          Button { visible: root.allowRemove; text: "Remove all copies"; onClicked: root.batchRemoveRequested(root.selectedItems()) }
          Button { text: "Clear"; onClicked: root.clearSelection() }
        }
      }
    }

    Loader {
      id: columnHeaders
      objectName: "media-column-headers"
      width: parent.width
      active: root.trackTable && root.showTableTools
      visible: active
      height: active && item ? item.implicitHeight : 0
      sourceComponent: Component {
        Row {
          width: columnHeaders.width
          spacing: Style.space(5)
          Button {
            text: root.compactRows ? "Compact" : "Comfortable"
            tooltipText: "Change track row density"
            onClicked: if (root.service) root.service.persistSettings({ trackDensity: root.compactRows ? "Comfortable" : "Compact" })
          }
          Button { text: "Columns"; tooltipText: root.columns; onClicked: root.cycleColumns() }
          Button { text: "Title"; onClicked: root.setSort("name") }
          Button { visible: root.albumColumn; text: "Album"; onClicked: root.setSort("album") }
          Button { visible: root.dateColumn; text: "Added"; onClicked: root.setSort(root.sortKey === "date" ? "date-asc" : "date") }
          Button { text: "Time"; onClicked: root.setSort("duration") }
        }
      }
    }

    ListView {
      id: mediaList
      width: parent.width
      height: Math.max(30, parent.height - tools.height - moreButton.height
        - emptyLabel.height - filterProgress.height - selectionTools.height
        - columnHeaders.height - parent.spacing * (
          (tools.visible && tools.height > 0 ? 1 : 0)
          + (selectionTools.visible && selectionTools.height > 0 ? 1 : 0)
          + (columnHeaders.visible && columnHeaders.height > 0 ? 1 : 0)
          + (emptyLabel.visible && emptyLabel.height > 0 ? 1 : 0)
          + (filterProgress.visible && filterProgress.height > 0 ? 1 : 0)
          + (moreButton.visible && moreButton.height > 0 ? 1 : 0)))
      // Keep metadata in JS; materialize only the rows the view actually needs.
      model: root.visibleItems.length
      clip: true
      spacing: Style.space(3)
      reuseItems: true
      cacheBuffer: Style.space(160)
      interactive: root.dragSourceIndex < 0
      activeFocusOnTab: false
      keyNavigationEnabled: false
      highlightFollowsCurrentItem: true
      ScrollBar.vertical: ScrollBar { }
      onMovementEnded: root.rememberView()
      onCountChanged: {
        root.restoreView()
        if (root.dragSourceIndex >= count) root.cancelReorder()
      }

      FastScrollHandler {
        parent: mediaList
        flickable: mediaList
        onScrolled: root.rememberView()
      }

      Keys.onPressed: function(event) {
        if (root.enableSelection && event.key === Qt.Key_A
            && (event.modifiers & Qt.ControlModifier)) {
          root.selectAll()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && root.selectionCount > 0) {
          root.clearSelection()
          event.accepted = true
        }
      }

      Keys.onReturnPressed: function(event) {
        if (!root.keyboardAtList) {
          event.accepted = false
          return
        }
        if (currentItem) currentItem.triggerPrimary()
        event.accepted = true
      }
      Keys.onEnterPressed: function(event) {
        if (!root.keyboardAtList) {
          event.accepted = false
          return
        }
        if (currentItem) currentItem.triggerPrimary()
        event.accepted = true
      }

      delegate: MediaRow {
        required property int index
        readonly property var rowItem: root.visibleItems[index] || null
        itemData: rowItem
        foreground: Color.foreground
        accent: Color.accent
        fontFamily: Style.font.family
        selected: root.isSelected(rowItem) || (ListView.isCurrentItem && root.keyboardAtList)
        selectionEnabled: root.enableSelection && !!rowItem && rowItem.kind === "item"
        compactRows: root.compactRows && root.trackTable
        albumColumn: root.albumColumn
        dateColumn: root.dateColumn
        draggedItems: root.isSelected(rowItem) ? root.selectedItems() : [rowItem]
        onSelectionRequested: function(modifiers) { root.selectRow(index, modifiers) }
        browseOnActivate: root.browseContexts && !!rowItem && rowItem.kind === "context"
        showQueue: root.showQueue
        showPlaylist: root.showPlaylist
        showSave: root.showSave
        reorderEnabled: root.canReorder
        reorderDragging: root.dragSourceIndex === index
        reorderDropIndicator: root.dragDestinationIndex === index
          && root.dragSourceIndex !== index
          ? (index < root.dragSourceIndex ? -1 : 1) : 0
        saved: root.service ? root.service.isSaved(rowItem) : false
        artworkEnabled: !root.service || root.service.artworkEnabled
        ShortcutHint {
          ctrlHeld: root.keyboardCtrlHeld
          shiftHeld: root.keyboardShiftHeld
          altHeld: root.keyboardAltHeld
          sequences: selected ? ["C"] : []
          active: root.keyboardHintsActive && (hint !== "" || selected)
          navHint: hint
          readonly property string hint: {
            mediaList.currentIndex
            mediaList.count
            mediaList.contentY
            root.keyboardAtList
            root.keyboardAtListPrev
            root.keyboardAtListNext
            root.keyboardListIsTab
            root.keyboardListIsBacktab
            root.keyboardNavModifiers
            root.keyboardHintsActive
            return root.rowNavHint(index)
          }
        }
        onActivated: function(item) {
          root.activated(item, root.visibleItems, root.playbackContextUri)
        }
        onOpenRequested: function(item) { root.opened(item) }
        onArtistRequested: function(item) { root.opened(item) }
        onAlbumRequested: function(item) { root.opened(item) }
        onQueueRequested: function(item) { root.queued(item) }
        onPlaylistRequested: function(item) { root.playlistRequested(item) }
        onSaveRequested: function(item) { root.saveToggled(item) }
        onContextRequested: function(item, sceneX, sceneY) {
          root.contextRequested(item, sceneX, sceneY, index,
            root.visibleItems, root.contextUri, root.playbackContextUri)
        }
        onReorderDragStarted: function(sceneY) {
          root.beginReorder(index, sceneY)
        }
        onReorderDragMoved: function(sceneY) { root.updateReorder(sceneY) }
        onReorderDragFinished: function(sceneY) {
          root.finishReorder(sceneY, false)
        }
        onReorderDragCanceled: root.cancelReorder()
      }
    }

    Text {
      id: emptyLabel
      width: parent.width
      height: visible ? contentHeight : 0
      visible: !root.loading && root.visibleItems.length === 0
      text: root.emptyMessage
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Flow {
      id: filterProgress
      width: parent.width
      height: visible ? implicitHeight : 0
      visible: root.filterText.trim() !== "" && root.hasMore
      spacing: Style.space(6)
      Text {
        text: "Filtering " + root.sourceItems.length + " loaded items. More remain."
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        width: Math.min(implicitWidth, parent.width)
        wrapMode: Text.WordWrap
      }
      Button {
        text: scanner.paused ? "Continue scan" : "Cancel scan"
        enabled: !scanner.blocked && !scanner.waitingForCooldown
        hasCursor: root.keyboardFilterScanSelected
        ShortcutHint { active: root.keyboardHintsActive; navHint: root.keyboardFilterScanHint }
        foreground: Color.foreground
        onClicked: scanner.paused ? scanner.resume() : scanner.cancel()
      }
    }

    Button {
      id: moreButton
      anchors.horizontalCenter: parent.horizontalCenter
      height: visible ? implicitHeight : 0
      visible: root.loading || root.hasMore
      text: root.loading ? "Loading…" : "Load more"
      foreground: Color.foreground
      enabled: root.hasMore && !root.loading
      hasCursor: root.keyboardMoreSelected
      onClicked: root.loadMoreRequested()
      ShortcutHint {
        active: root.keyboardHintsActive && root.keyboardMoreHint !== ""
        navHint: root.keyboardMoreHint
      }
    }
  }

  BorderSurface {
    id: dragPreview
    x: Style.space(4)
    width: Math.max(40, parent.width - Style.space(8))
    height: Style.space(48)
    y: Math.max(0, Math.min(parent.height - height,
      root.mapFromItem(null, 0, root.dragSceneY).y - height / 2))
    visible: root.dragSourceIndex >= 0 && !!root.dragItem
    enabled: false
    z: 20
    radius: Style.cornerRadius
    color: Style.selectedFillFor(Color.foreground, Color.accent)
    borderSpec: Border.controlSpec("selected", Color.foreground, Color.accent)
    opacity: 0.94

    Row {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(8)

      Column {
        width: parent.width
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          text: root.dragItem ? String(root.dragItem.name || "Untitled") : ""
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: root.dragItem ? String(root.dragItem.subtitle || "") : ""
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
