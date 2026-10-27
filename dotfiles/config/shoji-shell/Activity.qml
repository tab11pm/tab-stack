pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root
    readonly property bool enabled: Settings.enabled("activity")
    property bool loaded: false
    property bool manualPaused: false
    property bool viewing: false
    property string status: enabled ? "Запуск учёта…" : "Учёт выключен · включается отдельно"
    property string error: ""
    property var report: ({})
    property bool tracking: false
    property bool lockKnown: false
    property int lockSerial: 0
    property bool locked: true
    property string appId: ""
    property double sourceAt: 0
    property string selectedDate: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property string period: "day"
    property bool followToday: true
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("activity-tracker.py").toString().replace("file://", ""))

    function send(value) {
        if (!collector.running || !loaded) return;
        collector.write(JSON.stringify(value) + "\n");
    }
    function pushState() {
        send({ op: "state", appId: appId || null, idle: idle.isIdle,
            locked: !lockKnown || locked, connected: source.connected && Date.now() - sourceAt < 5000 });
    }
    function query() {
        send({ op: "query", date: selectedDate, period: period });
    }
    function toggle() {
        if (!loaded) { error = "Сборщик ещё не готов"; return; }
        pushState();
        send({ op: "toggle" });
        notice.command = ["notify-send", "--app-name=Время за ПК", "--expire-time=2200",
            "Время за ПК", manualPaused ? "Ручная пауза выключена" : "Агент работает / Я отошёл · учёт на паузе"];
        if (!notice.running) notice.running = true;
    }
    function toggleViewing() {
        if (!loaded) { error = "Сборщик ещё не готов"; return; }
        pushState();
        send({ op: "viewing", enabled: !viewing });
    }
    function setLocked(value) {
        lockSerial += 1;
        locked = value;
        lockKnown = true;
        pushState();
    }
    function selectPeriod(value, kind) {
        selectedDate = value;
        period = kind;
        followToday = value === Qt.formatDate(new Date(), "yyyy-MM-dd");
        query();
    }
    function focusState(view) {
        if (!view || !Array.isArray(view.monitors)) return;
        let focused = null;
        for (const monitor of view.monitors) {
            for (const workspace of monitor.workspaces || []) {
                for (const win of workspace.windows || []) {
                    if (win.focused && (!focused || (win.lastFocusedAt || 0) > (focused.lastFocusedAt || 0))) focused = win;
                }
            }
        }
        // Group variants of the compositor appId by their desktop entry.
        const raw = focused && typeof focused.appId === "string" ? focused.appId : "";
        const entry = raw ? (DesktopEntries.byId(raw) || DesktopEntries.heuristicLookup(raw)) : null;
        appId = entry ? entry.id : raw;
        sourceAt = Date.now();
        pushState();
    }
    function requestFocus() {
        if (!source.connected) return;
        source.write(JSON.stringify({ id: 8101, method: "workspaces.get" }) + "\n");
        source.flush();
    }
    Process {
        id: collector
        running: root.enabled
        stdinEnabled: true
        command: ["python3", root.script]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const value = JSON.parse(data);
                    if (!value.ready) { root.error = value.error || "Ошибка сборщика"; root.tracking = false; return; }
                    const first = !root.loaded;
                    root.loaded = true;
                    root.manualPaused = value.manualPaused === true;
                    root.viewing = value.viewing === true;
                    root.status = value.status;
                    root.tracking = value.tracking === true;
                    root.error = "";
                    // Do not display a reply to a superseded period request.
                    if (value.date === root.selectedDate && value.period === root.period) root.report = value;
                    if (first) { root.pushState(); root.query(); }
                } catch (failure) { root.error = "Не удалось прочитать статистику"; }
            }
        }
        onExited: {
            root.loaded = false;
            root.viewing = false;
            root.tracking = false;
            root.error = "Сборщик остановлен · повторный запуск через 5 секунд";
            if (root.enabled) restart.start();
        }
    }
    Timer { id: restart; interval: 5000; onTriggered: { if (root.enabled) collector.running = true; } }
    IdleMonitor {
        id: idle
        enabled: root.enabled
        timeout: 300
        respectInhibitors: false
        onIsIdleChanged: root.pushState()
    }
    Socket {
        id: source
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/shojiwm-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        connected: root.enabled
        onConnectionStateChanged: {
            if (connected) root.requestFocus();
            else { root.sourceAt = 0; root.appId = ""; root.pushState(); }
        }
        parser: SplitParser {
            onRead: data => {
                try {
                    const message = JSON.parse(data);
                    if (message.id === 8101 && message.result) root.focusState(message.result);
                    else if (message.event === "workspaces.changed") root.focusState(message.payload);
                } catch (failure) { root.sourceAt = 0; root.pushState(); }
            }
        }
    }
    Timer {
        interval: 1000; running: root.enabled; repeat: true
        onTriggered: {
            const today = Qt.formatDate(new Date(), "yyyy-MM-dd");
            if (root.followToday && root.selectedDate !== today) { root.selectedDate = today; root.query(); }
            root.pushState();
        }
    }
    Timer { interval: 2000; running: root.enabled; repeat: true; onTriggered: { if (!source.connected) source.connected = true; else root.requestFocus(); } }
    Process {
        id: lockProbe
        property int serial: 0
        onRunningChanged: { if (running) serial = root.lockSerial; }
        running: root.enabled
        command: ["python3", root.script, "--lock-status"]
        stdout: StdioCollector { id: lockReply; waitForEnd: true }
        onExited: exitCode => {
            if (serial !== root.lockSerial) return;
            try {
                const value = JSON.parse(lockReply.text);
                root.lockKnown = exitCode === 0 && value.known === true;
                root.locked = value.locked !== false;
            } catch (failure) { root.lockKnown = false; root.locked = true; }
            root.pushState();
        }
    }
    Timer { interval: 5000; running: root.enabled; repeat: true; onTriggered: { if (!lockProbe.running) lockProbe.running = true; } }
    Process { id: notice }
}
