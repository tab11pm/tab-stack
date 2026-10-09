pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool active: false
    property bool ready: false
    property bool dirty: false
    property bool busy: false
    property string error: ""
    property string primary: Settings.primaryOutput
    property string draftPrimary: ""
    property var outputs: []
    property var draft: []
    property string selected: ""
    property double deadline: 0
    property double now: Date.now()
    readonly property int remaining: Math.max(0, Math.ceil((deadline - now) / 1000))
    readonly property bool previewing: deadline > 0
    readonly property var current: draft.find(o => o.name === selected) || null
    property var document: null
    property bool loaded: false
    property int sequence: 0
    property var requests: ({})

    function send(method, params) {
        if (!socket.connected) { error = "Нет связи с ShojiWM"; busy = false; return; }
        const id = ++sequence;
        requests[id] = method;
        socket.write(JSON.stringify({ id, method, params: params || {} }) + "\n");
        socket.flush();
    }
    function start() {
        if (!loaded || !socket.connected) return;
        if (document) send("monitors.restore", document);
        else send("monitors.get");
    }
    function reset() {
        draft = outputs.map(o => Object.assign({}, o));
        draftPrimary = outputs.some(o => o.name === primary) ? primary : (outputs[0] || {}).name || "";
        if (!draft.some(o => o.name === selected)) selected = draftPrimary;
        dirty = false;
    }
    function update(name, patch) {
        if (previewing || busy) return;
        draft = draft.map(o => o.name === name ? Object.assign({}, o, patch) : o);
        dirty = true;
    }
    function makePrimary() { draftPrimary = selected; dirty = true; }
    function apply() {
        error = ""; busy = true;
        const layoutOnly = draft.every(o => {
            const actual = outputs.find(item => item.name === o.name);
            return actual && actual.width === o.width && actual.height === o.height
                && Math.abs(actual.scale - o.scale) < 0.01
                && Math.abs(actual.refreshRate - o.refreshRate) < 0.01;
        });
        send(layoutOnly ? "monitors.apply-layout" : "monitors.preview", { primary: draftPrimary, outputs: draft.map(o => ({
            name: o.name, x: Math.round(o.x), y: Math.round(o.y), scale: o.scale,
            width: o.width, height: o.height, refreshRate: o.refreshRate
        })) });
    }
    function confirm() { busy = true; send("monitors.confirm"); }
    function cancel() { busy = true; send("monitors.cancel"); }
    function accept(result, resetDraft) {
        const changed = outputs.map(o => o.name).join() !== result.outputs.map(o => o.name).join();
        outputs = result.outputs;
        primary = result.primary || Settings.primaryOutput;
        deadline = result.deadline || 0;
        now = Date.now();
        ready = true;
        const lostDraft = changed && dirty;
        if (resetDraft || changed || (!dirty && !previewing)) reset();
        if (lostDraft) error = "Состав мониторов изменился. Проверь настройки заново.";
    }
    onActiveChanged: { if (active) send("monitors.get"); }
    Connections {
        target: Quickshell
        function onScreensChanged(): void { if (root.ready) root.send("monitors.get"); }
    }
    Timer { interval: 1000; repeat: true; running: root.previewing; onTriggered: root.now = Date.now() }
    Timer { interval: 3000; repeat: true; running: root.active && !root.busy; onTriggered: root.send("monitors.get") }
    Timer { interval: 2000; repeat: true; running: !socket.connected; onTriggered: socket.connected = true }
    FileView {
        id: storage
        path: Settings.configHome + "/shoji-shell/monitors.json"
        preload: true; printErrors: false; atomicWrites: true
        onLoaded: {
            if (root.loaded) return;
            try { root.document = JSON.parse(text()); }
            catch (failure) { root.error = "Не удалось прочитать сохранённые настройки мониторов"; }
            root.loaded = true; root.start();
        }
        onLoadFailed: failure => {
            root.loaded = true;
            if (failure !== FileViewError.FileNotFound) root.error = "Не удалось загрузить настройки мониторов";
            root.start();
        }
        onSaveFailed: root.error = "Настройки применены, но не сохранены на диск"
    }
    Socket {
        id: socket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/shojiwm-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        connected: true
        onConnectionStateChanged: {
            if (connected) root.start();
            else { root.ready = false; root.busy = false; root.requests = ({}); }
        }
        parser: SplitParser {
            onRead: data => {
                try {
                    const message = JSON.parse(data);
                    if (message.event === "monitors.changed") {
                        const ended = root.previewing && !message.payload.deadline;
                        root.accept(message.payload, ended);
                        return;
                    }
                    const method = root.requests[message.id];
                    if (!method) return;
                    delete root.requests[message.id];
                    root.busy = false;
                    if (message.error) {
                        root.error = typeof message.error === "string" ? message.error : message.error.message || "Не удалось изменить настройки. Перезагрузи конфиг: Super+Shift+R.";
                        return;
                    }
                    const saved = method === "monitors.confirm" || method === "monitors.apply-layout";
                    if (method === "monitors.apply-layout") {
                        // reconfigure queues the native change; its immediate snapshot
                        // can still contain the old positions. Keep the accepted layout.
                        message.result.outputs = message.result.outputs.map(o => Object.assign({}, o,
                            message.result.settings.outputs.find(item => item.name === o.name) || {}));
                    }
                    root.accept(message.result, method === "monitors.cancel" || saved || method === "monitors.restore");
                    if (saved) {
                        root.document = message.result.settings;
                        storage.setText(JSON.stringify(root.document, null, 2));
                    }
                } catch (failure) { root.busy = false; root.error = "Не удалось прочитать ответ ShojiWM"; }
            }
        }
    }
}
