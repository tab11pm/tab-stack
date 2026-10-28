import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: row
    property string label
    property var options: []
    property real value: 0
    signal chosen(real value)
    Layout.fillWidth: true
    UiText { text: row.label; color: Theme.muted; font.pixelSize: 11; Layout.fillWidth: true }
    ComboBox {
        id: control
        model: row.options; textRole: "label"; valueRole: "value"
        currentIndex: row.options.findIndex(o => Math.abs(o.value - row.value) < 0.01)
        displayText: currentIndex >= 0 ? row.options[currentIndex].label : String(row.value)
        enabled: !!Monitors.current && !Monitors.previewing && !Monitors.busy && row.options.length > 0
        implicitWidth: 122; implicitHeight: 32
        font.family: Theme.font; font.pixelSize: 11
        palette.text: Theme.ink; palette.buttonText: Theme.ink; palette.window: Theme.raised
        palette.base: Theme.raised; palette.highlight: Theme.accent; palette.highlightedText: Theme.surface
        background: Rectangle { color: control.hovered ? Theme.hover : Theme.raised; radius: 8; border.color: control.visualFocus ? Theme.accent : "transparent"; border.width: 1 }
        Accessible.name: row.label
        onActivated: row.chosen(row.options[currentIndex].value)
    }
}
