import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

Controls.Popup {
  id: editor
  required property var controller
  property var playlist: null
  x: Math.max(8, (parent.width - width) / 2)
  y: Math.max(8, (parent.height - height) / 2)
  width: Math.min(420, parent.width - 32)
  padding: Style.space(16)
  modal: true
  focus: true
  closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
  onOpened: {
    nameField.text = playlist ? String(playlist.name || "") : ""
    descriptionField.text = playlist ? String(playlist.description || "") : ""
    nameField.forceActiveFocus()
  }
  background: BorderSurface {
    color: editor.controller.popupBackground
    radius: Style.cornerRadius
    borderSpec: editor.controller.popupBorderSpec
  }
  contentItem: Column {
    spacing: Style.space(8)
    Text {
      text: "Edit playlist"
      color: editor.controller.foreground
      font.family: editor.controller.fontFamily
      font.pixelSize: Style.font.subtitle
    }
    TextField {
      id: nameField
      width: parent.width
      maximumLength: 100
      foreground: editor.controller.foreground
      placeholderText: "Playlist name"
      Accessible.name: "Playlist name"
    }
    Controls.TextArea {
      id: descriptionField
      width: parent.width
      height: Style.space(120)
      color: editor.controller.foreground
      placeholderText: "Description"
      wrapMode: TextEdit.Wrap
      selectByMouse: true
      Accessible.name: "Playlist description"
      onTextChanged: if (length > 300) remove(300, length)
      background: BorderSurface {
        color: editor.controller.background
        borderSpec: Border.controlSpec("normal", editor.controller.foreground, editor.controller.accent)
      }
    }
    Row {
      spacing: Style.space(8)
      Button {
        text: "Save"
        enabled: editor.controller.service && !editor.controller.service.playlistActionBusy
          && nameField.text.trim() !== ""
        onClicked: {
          editor.controller.service.updatePlaylistDetails(editor.playlist, nameField.text, descriptionField.text)
          editor.close()
        }
      }
      Button { text: "Cancel"; onClicked: editor.close() }
    }
  }
}
