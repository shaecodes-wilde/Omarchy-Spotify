import QtQuick

ShortcutHint {
  id: hint
  required property var controller
  readonly property var panel: controller
  property string region: ""
  property string action: ""
  ctrlHeld: panel.hintCtrlHeld
  shiftHeld: panel.hintShiftHeld
  altHeld: panel.hintAltHeld
  active: panel.shortcutHintsActive
  navHint: {
    if (!hint.active) return ""
    panel.panelCursorAction
    panel.panelCursorRegion
    panel.panelCursorVisible
    panel.panelCursorActive
    panel.shortcutModeLatched
    panel.hintCtrlHeld
    panel.hintShiftHeld
    panel.hintAltHeld
    panel.sidebarPlaylistCursorIndex
    panel.searchFieldFocused
    return region && action ? panel.navHintFor(region, action) : ""
  }
  foreground: panel.foreground
  accent: panel.accent
}
