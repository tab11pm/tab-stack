pragma ComponentBehavior: Bound
import QtQuick
import "lock"

// Settings preview of our own locker view; no locking or PAM runs here.
Item {
    id: preview
    required property var output
    required property url wallpaperSource
    property var wallpaperFrame: null
    property string stateName: "input"
    readonly property var faceItem: face
    readonly property int imageStatus: Image.Ready
    implicitHeight: width * (output ? output.height / Math.max(1, output.width) : 9 / 16)
    clip: true
    LockView {
        id: face
        preview: true
        inputEnabled: false
        backgroundUrl: preview.wallpaperSource
        busy: preview.stateName === "checking"
        errorMessage: preview.stateName === "error" ? "Неверный пароль" : ""
        passwordText: "preview"
        layoutName: "EN"
        width: preview.output ? preview.output.width : 1920
        height: preview.output ? preview.output.height : 1080
        scale: Math.min(preview.width / Math.max(1, width), preview.height / Math.max(1, height))
        transformOrigin: Item.TopLeft
        x: (preview.width - width * scale) / 2
        y: (preview.height - height * scale) / 2
    }
    // Display-only: no keyboard or pointer input reaches the view.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
}
