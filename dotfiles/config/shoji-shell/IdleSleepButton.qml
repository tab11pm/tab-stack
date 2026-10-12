import QtQuick
import QtQuick.Controls

ActionButton {
    id: control
    width: 34; height: 34
    padding: 8
    enabled: IdleSleep.loaded
    checkable: true
    checked: IdleSleep.enabled
    hint: (IdleSleep.enabled
        ? "Я отошёл · " + IdleSleep.status + "\nНажми, чтобы работать без автосна"
        : "Я работаю · автосон выключен\nНажми, чтобы включить автосон")
        + (IdleSleep.storageError || IdleSleep.error ? "\n" + (IdleSleep.storageError || IdleSleep.error) : "")
    icon.source: Qt.resolvedUrl("icons/moon.svg")
    icon.color: IdleSleep.enabled ? Theme.accent : Theme.muted
    background: Rectangle {
        radius: 17
        color: control.hovered ? Theme.hover : Theme.surface
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.accent
    }
    ToolTip.visible: hovered
    ToolTip.delay: 400
    ToolTip.text: hint
    onClicked: IdleSleep.toggle()
}
