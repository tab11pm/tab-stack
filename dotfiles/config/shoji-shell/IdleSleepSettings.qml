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
        UiText { text: "Автосон"; font.weight: Font.Medium; Layout.fillWidth: true }
        UiText {
            text: IdleSleep.status
            color: Theme.muted; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: [1, 5, 10]
                ActionButton {
                    required property int modelData
                    Layout.fillWidth: true; Layout.preferredWidth: 1
                    text: modelData + " мин"
                    font.pixelSize: 11; padding: 8
                    highlighted: IdleSleep.minutes === modelData
                    enabled: IdleSleep.loaded
                    hint: "Сон через " + modelData + (modelData === 1 ? " минуту" : " минут") + " бездействия"
                    onClicked: IdleSleep.setMinutes(modelData)
                }
            }
        }
        UiText {
            text: "Включение и выключение — кнопкой луны в верхней панели"
            color: Theme.muted; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        UiText {
            text: IdleSleep.storageError || IdleSleep.error
            visible: text !== ""; color: Theme.danger; font.pixelSize: 10
            wrapMode: Text.Wrap; Layout.fillWidth: true
        }
    }
}
