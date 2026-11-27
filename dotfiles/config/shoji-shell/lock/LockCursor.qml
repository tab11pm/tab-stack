import QtQuick
import Quickshell.Io
import ".." as Desktop

// ShojiWM draws no overlays while the session is locked, so the locker draws the cursor effect itself.
Item {
    id: root
    property string mode: "none"
    readonly property bool shown: mode !== "none" && hover.hovered
    property point pos: Qt.point(0, 0)

    FileView {
        path: Desktop.Settings.configHome + "/shoji-shell/cursor-fx.json"
        preload: true; printErrors: false
        onLoaded: { try { root.mode = JSON.parse(text()).mode || "none"; } catch (failure) { root.mode = "none"; } }
    }
    // Passive: clicks and typing still reach the password field underneath.
    HoverHandler { id: hover; cursorShape: root.mode === "none" ? Qt.ArrowCursor : Qt.BlankCursor }
    // Same exponential lag as cursor-fx.ts.
    FrameAnimation {
        running: root.shown
        onTriggered: {
            const k = 1 - Math.exp(-Math.min(0.1, frameTime) * 16);
            const p = hover.point.position;
            root.pos = Qt.point(root.pos.x + (p.x - root.pos.x) * k, root.pos.y + (p.y - root.pos.y) * k);
        }
    }
    Rectangle {
        visible: root.shown
        readonly property real size: root.mode === "ring" ? 30 : 26
        x: root.pos.x - size / 2; y: root.pos.y - size / 2
        width: size; height: size; radius: size / 2
        color: root.mode === "ring" ? "transparent" : "#d9ff99d6"
        border.width: root.mode === "ring" ? 2.4 : 0
        border.color: "white"
    }
    Rectangle {
        visible: root.shown
        readonly property real size: root.mode === "ring" ? 6 : 8
        x: hover.point.position.x - size / 2; y: hover.point.position.y - size / 2
        width: size; height: size; radius: size / 2
        color: root.mode === "ring" ? "white" : "#7a5cff"
    }
}
