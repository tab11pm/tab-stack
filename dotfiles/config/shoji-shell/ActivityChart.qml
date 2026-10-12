pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var bars: []
    property string period: "day"
    readonly property real peak: Math.max(60, ...bars.map(value => value.seconds || 0))
    implicitHeight: 112
    function duration(seconds) {
        const total = Math.floor(seconds || 0);
        const minutes = Math.floor(total / 60);
        if (total < 60) return total + " с";
        const remainder = " " + total % 60 + " с";
        return (minutes >= 60 ? Math.floor(minutes / 60) + " ч " + minutes % 60 + " мин" : minutes + " мин") + remainder;
    }
    Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: Theme.line; opacity: 0.2 }
    Rectangle { x: 0; y: (parent.height - 25) / 2; width: parent.width; height: 1; color: Theme.line; opacity: 0.2 }
    Rectangle { x: 0; y: parent.height - 25; width: parent.width; height: 1; color: Theme.line; opacity: 0.45 }
    Row {
        id: barsRow
        anchors.fill: parent
        spacing: root.period === "week" ? 10 : 3
        Repeater {
            model: root.bars
            Item {
                id: column
                required property var modelData
                required property int index
                width: root.bars.length ? (root.width - (root.bars.length - 1) * barsRow.spacing) / root.bars.length : 0
                height: root.height
                Rectangle {
                    width: parent.width
                    height: column.modelData.seconds > 0 ? Math.max(2, (column.height - 29) * column.modelData.seconds / root.peak) : 0
                    anchors.bottom: label.top
                    anchors.bottomMargin: 6
                    radius: Math.min(4, width / 2)
                    color: Theme.accent
                    opacity: hover.containsMouse ? 1 : 0.8
                }
                UiText {
                    id: label
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 19
                    text: column.modelData.label
                    visible: root.period === "week" || column.index % 4 === 0 || column.index === 23
                    font.pixelSize: 10
                    color: Theme.muted
                    horizontalAlignment: Text.AlignHCenter
                }
                MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                ToolTip.visible: hover.containsMouse
                ToolTip.delay: 150
                ToolTip.text: (root.period === "day" ? column.modelData.label + ":00 · " : column.modelData.label + " · ") + root.duration(column.modelData.seconds)
                Accessible.role: Accessible.StaticText
                Accessible.name: ToolTip.text
            }
        }
    }
}
