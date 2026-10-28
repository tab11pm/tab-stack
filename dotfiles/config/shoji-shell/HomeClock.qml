pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

Item {
    id: root
    property bool showSeconds: false
    implicitWidth: 852
    implicitHeight: 228
    readonly property string timeText: Qt.formatDateTime(clock.date, showSeconds ? "hh:mm:ss" : "hh:mm")
    readonly property string richTime: timeText.split(":").join("<font color='#cba6f7'>:</font>")
    readonly property string dateLabel: Qt.locale("ru_RU").toString(clock.date, "dddd · dd MMMM").toUpperCase()
    SystemClock { id: clock; precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes }

    Accessible.role: Accessible.Clock
    Accessible.name: root.timeText

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 18
        width: parent.width
        height: 132
        text: root.richTime
        textFormat: Text.RichText
        font.family: Theme.font
        font.pixelSize: 120
        font.weight: Font.DemiBold
        font.letterSpacing: -4
        color: Theme.ink
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    UiText {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 164
        width: parent.width
        text: root.dateLabel
        color: Theme.muted
        font.family: "Noto Sans Mono"
        font.pixelSize: 12
        font.letterSpacing: 1.2
        horizontalAlignment: Text.AlignHCenter
    }
}
