pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    readonly property real ratio: width / 852

    Repeater {
        model: [
            { x: 0, y: 242, w: 252, h: 170, color: Theme.surface },
            { x: 270, y: 266, w: 276, h: 170, color: Theme.surface },
            { x: 564, y: 234, w: 122, h: 122, color: Theme.raised },
            { x: 616, y: 296, w: 236, h: 144, color: Theme.surface },
            { x: 4, y: 430, w: 76, h: 104, color: Theme.surface },
            { x: 90, y: 442, w: 76, h: 104, color: Theme.surface },
            { x: 176, y: 430, w: 76, h: 104, color: Theme.surface },
            { x: 0, y: 562, w: 252, h: 120, color: Theme.surface },
            { x: 270, y: 454, w: 285, h: 84, color: "#d8cdea" },
            { x: 567, y: 462, w: 285, h: 84, color: "#efd0c0" },
            { x: 270, y: 558, w: 187.33, h: 124, color: "#c7e0d7" },
            { x: 467.33, y: 558, w: 187.33, h: 124, color: "#e6cddd" },
            { x: 664.66, y: 558, w: 187.33, h: 124, color: "#cbdcf0" }
        ]
        Rectangle {
            required property var modelData
            x: modelData.x * root.ratio; y: modelData.y * root.ratio
            width: modelData.w * root.ratio; height: modelData.h * root.ratio
            radius: Math.max(1, 20 * root.ratio)
            color: modelData.color
        }
    }

    Text {
        x: 60 * root.ratio
        y: 14 * root.ratio
        width: 732 * root.ratio
        height: 137 * root.ratio
        text: "08<font color='#cba6f7'>:</font>42"
        textFormat: Text.RichText
        font.family: Theme.font
        font.pixelSize: 120 * root.ratio
        font.weight: Font.DemiBold
        font.letterSpacing: -4 * root.ratio
        color: Theme.ink
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    UiText {
        x: 0; y: 163 * root.ratio; width: 852 * root.ratio
        text: "ВТОРНИК · 20 ОКТЯБРЯ"
        color: Theme.muted
        font.family: "Noto Sans Mono"
        font.pixelSize: 10 * root.ratio
        font.letterSpacing: 1.1 * root.ratio
        horizontalAlignment: Text.AlignHCenter
    }
}
