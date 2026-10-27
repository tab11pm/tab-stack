pragma ComponentBehavior: Bound
import QtQuick
import "WidgetLayoutState.js" as LayoutState

Item {
    id: root
    required property var draft
    required property var screens
    required property string primary
    property string selectedId: ""
    signal selected(string widgetId)
    signal moved(string widgetId, string outputName, real localX, real localY)
    readonly property real desktopLeft: screens.length ? Math.min(...screens.map(s => s.x)) : 0
    readonly property real desktopTop: screens.length ? Math.min(...screens.map(s => s.y)) : 0
    readonly property real desktopWidth: screens.length ? Math.max(...screens.map(s => s.x + s.width)) - desktopLeft : 1
    readonly property real desktopHeight: screens.length ? Math.max(...screens.map(s => s.y + s.height)) - desktopTop : 1
    readonly property real factor: Math.max(0.001, Math.min((width - 32) / desktopWidth, (height - 56) / desktopHeight))
    readonly property real originX: (width - desktopWidth * factor) / 2
    readonly property real originY: (height - desktopHeight * factor) / 2 + 8

    function screenAt(x, y) {
        return screens.find(s => x >= originX + (s.x - desktopLeft) * factor
            && x <= originX + (s.x + s.width - desktopLeft) * factor
            && y >= originY + (s.y - desktopTop) * factor
            && y <= originY + (s.y + s.height - desktopTop) * factor) || null;
    }
    function sizeFor(id, screen) {
        const entry = LayoutState.catalog.find(item => item.id === id);
        if (!entry) return { width: 100, height: 80 };
        const scale = Math.min(1, (screen.width - 32) / entry.width, (screen.height - 152) / entry.height);
        return { width: entry.width * Math.max(0, scale), height: entry.height * Math.max(0, scale) };
    }
    Rectangle { anchors.fill: parent; radius: 10; color: Theme.surface; border.color: Theme.line }
    Repeater {
        model: root.screens
        delegate: Rectangle {
            id: monitor
            required property var modelData
            x: root.originX + (modelData.x - root.desktopLeft) * root.factor
            y: root.originY + (modelData.y - root.desktopTop) * root.factor
            width: modelData.width * root.factor
            height: modelData.height * root.factor
            color: Theme.raised; border.color: Theme.line; radius: 3
            UiText {
                anchors { bottom: parent.top; bottomMargin: 5; left: parent.left; right: parent.right }
                text: monitor.modelData.name; font.pixelSize: 11; color: Theme.muted
            }
            Repeater {
                model: Object.keys(root.draft.layout.widgets).filter(id =>
                    LayoutState.resolveOutput(root.draft.layout.widgets[id].output, root.screens, root.primary) === monitor.modelData.name)
                delegate: Rectangle {
                    id: tile
                    objectName: "widget-" + modelData
                    required property string modelData
                    readonly property var entry: LayoutState.catalog.find(item => item.id === modelData)
                    readonly property var placement: root.draft.layout.widgets[modelData]
                    readonly property var logicalSize: root.sizeFor(modelData, monitor.modelData)
                    readonly property var position: LayoutState.clampPosition(
                        LayoutState.toPosition(placement, logicalSize.width, logicalSize.height, monitor.modelData).x,
                        LayoutState.toPosition(placement, logicalSize.width, logicalSize.height, monitor.modelData).y,
                        logicalSize.width, logicalSize.height, monitor.modelData)
                    x: position.x * root.factor; y: position.y * root.factor
                    width: Math.max(20, logicalSize.width * root.factor)
                    height: Math.max(18, logicalSize.height * root.factor)
                    radius: 3; z: root.selectedId === modelData ? 2 : 1
                    color: root.selectedId === modelData ? Qt.tint(Theme.raised, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)) : Theme.hover
                    border.color: root.selectedId === modelData ? Theme.accent : Theme.line
                    border.width: root.selectedId === modelData ? 2 : 1
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: (entry ? entry.label : modelData) + " · " + monitor.modelData.name
                    Accessible.onPressAction: root.selected(tile.modelData)
                    Keys.onPressed: event => {
                        const shifts = ({ [Qt.Key_Left]: [-10, 0], [Qt.Key_Right]: [10, 0], [Qt.Key_Up]: [0, -10], [Qt.Key_Down]: [0, 10] });
                        const shift = shifts[event.key];
                        if (!shift) return;
                        root.selected(tile.modelData);
                        root.moved(tile.modelData, monitor.modelData.name, tile.position.x + shift[0], tile.position.y + shift[1]);
                        event.accepted = true;
                    }
                    UiText { anchors.fill: parent; anchors.margins: 4; text: tile.entry ? tile.entry.label : tile.modelData; font.pixelSize: 10; wrapMode: Text.Wrap; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property real offsetX: 0
                        property real offsetY: 0
                        property real initialX: 0
                        property real initialY: 0
                        property bool dragged: false
                        onPressed: mouse => {
                            root.selected(tile.modelData); tile.forceActiveFocus();
                            const point = tile.mapToItem(root, 0, 0);
                            offsetX = mouse.x; offsetY = mouse.y;
                            initialX = point.x; initialY = point.y; dragged = false;
                            proxy.x = point.x; proxy.y = point.y;
                            proxy.width = tile.width; proxy.height = tile.height;
                            proxy.label = tile.entry ? tile.entry.label : tile.modelData;
                        }
                        onPositionChanged: mouse => {
                            if (!pressed) return;
                            const point = mapToItem(root, mouse.x, mouse.y);
                            proxy.x = point.x - offsetX; proxy.y = point.y - offsetY;
                            if (Math.abs(proxy.x - initialX) + Math.abs(proxy.y - initialY) > 3) dragged = true;
                            proxy.visible = dragged;
                        }
                        onReleased: {
                            proxy.visible = false;
                            if (!dragged) return;
                            const screen = root.screenAt(proxy.x + proxy.width / 2, proxy.y + proxy.height / 2);
                            if (!screen) return;
                            root.moved(tile.modelData, screen.name,
                                (proxy.x - root.originX) / root.factor - (screen.x - root.desktopLeft),
                                (proxy.y - root.originY) / root.factor - (screen.y - root.desktopTop));
                        }
                        onCanceled: proxy.visible = false
                    }
                }
            }
        }
    }
    Rectangle {
        id: proxy
        property string label: ""
        visible: false; z: 10; radius: 3
        color: Theme.hover; opacity: 0.85; border.color: Theme.accent; border.width: 2
        UiText { anchors.centerIn: parent; text: proxy.label; font.pixelSize: 10 }
    }
    UiText { anchors.centerIn: parent; visible: root.screens.length === 0; text: "Нет подключённых мониторов"; color: Theme.muted }
}
