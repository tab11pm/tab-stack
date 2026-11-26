pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 24
    radius: 8
    color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.035)
    border.width: 1; border.color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.07)
    ColumnLayout {
        id: content
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
        spacing: 8
        UiText { text: "Курсор"; font.weight: Font.Medium; Layout.fillWidth: true }
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: CursorFx.modes
                ActionButton {
                    required property var modelData
                    Layout.fillWidth: true; Layout.preferredWidth: 1
                    text: modelData.title
                    font.pixelSize: 11; padding: 8
                    highlighted: CursorFx.mode === modelData.id
                    enabled: CursorFx.loaded
                    hint: "Эффект курсора: " + modelData.title
                    onClicked: CursorFx.setMode(modelData.id)
                }
            }
        }
        UiText {
            text: CursorFx.error
            visible: text !== ""; color: Theme.danger; font.pixelSize: 10
            wrapMode: Text.Wrap; Layout.fillWidth: true
        }
    }
}
