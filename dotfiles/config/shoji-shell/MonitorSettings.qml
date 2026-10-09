pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: panel
    property bool active: visible
    spacing: 10
    Binding { target: Monitors; property: "active"; value: panel.active }
    UiText { text: "Перетащи экраны, чтобы повторить их расположение на столе."; color: Theme.muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Rectangle {
        id: canvas
        Layout.fillWidth: true; Layout.preferredHeight: 180
        radius: 8; color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.035)
        border.width: 1; border.color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.07)
        clip: true
        property bool dragging: false
        property var bounds: ({ x: 0, y: 0, w: 1920, h: 1080 })
        readonly property real ratio: Math.min((width - 64) / bounds.w, (height - 52) / bounds.h)
        function fit() {
            if (dragging || !Monitors.draft.length) return;
            const list = Monitors.draft;
            const x = Math.min(...list.map(o => o.x)), y = Math.min(...list.map(o => o.y));
            bounds = { x, y, w: Math.max(...list.map(o => o.x + o.width / o.scale)) - x,
                h: Math.max(...list.map(o => o.y + o.height / o.scale)) - y };
        }
        Component.onCompleted: fit()
        onWidthChanged: fit()
        Connections { target: Monitors; function onDraftChanged(): void { canvas.fit(); } }
        Repeater {
            model: Monitors.draft
            Rectangle {
                id: tile
                required property var modelData
                required property int index
                x: (canvas.width - canvas.bounds.w * canvas.ratio) / 2 + (modelData.x - canvas.bounds.x) * canvas.ratio
                y: (canvas.height - canvas.bounds.h * canvas.ratio) / 2 + (modelData.y - canvas.bounds.y) * canvas.ratio
                width: modelData.width / modelData.scale * canvas.ratio
                height: modelData.height / modelData.scale * canvas.ratio
                function restorePosition() {
                    x = Qt.binding(() => (canvas.width - canvas.bounds.w * canvas.ratio) / 2 + (modelData.x - canvas.bounds.x) * canvas.ratio);
                    y = Qt.binding(() => (canvas.height - canvas.bounds.h * canvas.ratio) / 2 + (modelData.y - canvas.bounds.y) * canvas.ratio);
                }
                radius: 6; color: Monitors.selected === modelData.name ? Theme.raised : Theme.surface
                border.width: Monitors.selected === modelData.name || activeFocus ? 2 : 1
                border.color: Monitors.selected === modelData.name || activeFocus ? Theme.accent : Theme.line
                focus: false; activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Монитор " + modelData.name + ". Стрелки перемещают, Enter выбирает."
                Keys.onReturnPressed: Monitors.selected = modelData.name
                Keys.onPressed: event => {
                    const moves = {}; moves[Qt.Key_Left] = [-20, 0]; moves[Qt.Key_Right] = [20, 0];
                    moves[Qt.Key_Up] = [0, -20]; moves[Qt.Key_Down] = [0, 20];
                    if (moves[event.key] && !Monitors.previewing && !Monitors.busy) {
                        Monitors.selected = modelData.name;
                        Monitors.update(modelData.name, { x: modelData.x + moves[event.key][0], y: modelData.y + moves[event.key][1] });
                        event.accepted = true;
                    }
                }
                Column {
                    anchors.centerIn: parent; width: parent.width - 8; spacing: 2
                    UiText { width: parent.width; text: tile.index + 1; font.pixelSize: 22; color: Monitors.selected === tile.modelData.name ? Theme.accent : Theme.ink; horizontalAlignment: Text.AlignHCenter }
                    UiText { width: parent.width; text: tile.modelData.name; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                    UiText { width: parent.width; text: Monitors.draftPrimary === tile.modelData.name ? "Главный" : ""; color: Theme.accent; font.pixelSize: 9; horizontalAlignment: Text.AlignHCenter }
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    enabled: !Monitors.previewing && !Monitors.busy
                    drag.target: tile
                    drag.minimumX: 4; drag.maximumX: canvas.width - tile.width - 4
                    drag.minimumY: 4; drag.maximumY: canvas.height - tile.height - 4
                    property real startX: 0
                    property real startY: 0
                    onPressed: { Monitors.selected = tile.modelData.name; tile.forceActiveFocus(); canvas.dragging = true; startX = tile.x; startY = tile.y; }
                    onReleased: {
                        let x = Math.round(tile.modelData.x + (tile.x - startX) / canvas.ratio);
                        let y = Math.round(tile.modelData.y + (tile.y - startY) / canvas.ratio);
                        const w = tile.modelData.width / tile.modelData.scale, h = tile.modelData.height / tile.modelData.scale;
                        let best = null, distance = Infinity;
                        for (const other of Monitors.draft.filter(o => o.name !== tile.modelData.name)) {
                            const ow = other.width / other.scale, oh = other.height / other.scale;
                            const candidates = [
                                { x: other.x + ow, y: Math.max(other.y - h + 1, Math.min(y, other.y + oh - 1)) },
                                { x: other.x - w, y: Math.max(other.y - h + 1, Math.min(y, other.y + oh - 1)) },
                                { x: Math.max(other.x - w + 1, Math.min(x, other.x + ow - 1)), y: other.y + oh },
                                { x: Math.max(other.x - w + 1, Math.min(x, other.x + ow - 1)), y: other.y - h }
                            ];
                            for (const p of candidates) {
                                const overlaps = Monitors.draft.some(o => o.name !== tile.modelData.name && p.x < o.x + o.width / o.scale - 0.5 && p.x + w > o.x + 0.5 && p.y < o.y + o.height / o.scale - 0.5 && p.y + h > o.y + 0.5);
                                const d = Math.hypot(p.x - x, p.y - y);
                                if (!overlaps && d < distance) { best = p; distance = d; }
                            }
                        }
                        if (best) { x = Math.round(best.x); y = Math.round(best.y); }
                        const moved = Math.abs(tile.x - startX) + Math.abs(tile.y - startY) > 2;
                        canvas.dragging = false;
                        tile.restorePosition();
                        if (moved) Monitors.update(tile.modelData.name, { x, y });
                        canvas.fit();
                    }
                    onCanceled: { canvas.dragging = false; tile.restorePosition(); canvas.fit(); }
                }
            }
        }
        UiText { anchors.centerIn: parent; visible: !Monitors.ready; text: "Загрузка мониторов…"; color: Theme.muted; font.pixelSize: 11 }
    }
    Flow {
        Layout.fillWidth: true; spacing: 6
        Repeater {
            model: Monitors.draft
            ActionButton {
                required property var modelData
                text: modelData.name; highlighted: Monitors.selected === modelData.name
                onClicked: Monitors.selected = modelData.name
            }
        }
    }
    UiText { text: Monitors.current ? Monitors.current.description : "Нет подключённых экранов"; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
    RowLayout {
        Layout.fillWidth: true
        UiText { text: "Главный экран"; color: Theme.muted; font.pixelSize: 11; Layout.fillWidth: true }
        ActionButton {
            text: Monitors.selected === Monitors.draftPrimary ? "Главный" : "Сделать главным"
            highlighted: Monitors.selected === Monitors.draftPrimary
            enabled: !!Monitors.current && !Monitors.previewing && !Monitors.busy
            onClicked: Monitors.makePrimary()
        }
    }
    MonitorChoice {
        label: "Частота обновления"
        options: Monitors.current ? Monitors.current.modes.filter(m => m.width === Monitors.current.width && m.height === Monitors.current.height).map(m => ({ label: Math.round(m.refreshRate * 100) / 100 + " Гц", value: m.refreshRate })) : []
        value: Monitors.current ? Monitors.current.refreshRate : 0
        onChosen: value => Monitors.update(Monitors.selected, { refreshRate: value })
    }
    MonitorChoice {
        label: "Масштаб"
        options: [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3].map(s => ({ label: s * 100 + "%", value: s }))
        value: Monitors.current ? Monitors.current.scale : 1
        onChosen: value => Monitors.update(Monitors.selected, { scale: value })
    }
    UiText { visible: Monitors.error !== ""; text: Monitors.error; color: Theme.danger; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
    UiText { visible: Monitors.previewing; text: "Сохранить настройки? Возврат через " + Monitors.remaining + " с."; color: Theme.accent; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        ActionButton { text: Monitors.previewing ? "Вернуть" : "Сбросить"; enabled: !Monitors.busy && (Monitors.dirty || Monitors.previewing); onClicked: Monitors.previewing ? Monitors.cancel() : Monitors.reset() }
        Item { Layout.fillWidth: true }
        ActionButton { text: Monitors.busy ? "Применение…" : Monitors.previewing ? "Сохранить" : "Применить"; highlighted: true; enabled: Monitors.ready && !Monitors.busy && (Monitors.dirty || Monitors.previewing); onClicked: Monitors.previewing ? Monitors.confirm() : Monitors.apply() }
    }
}
