pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NightLightSchedule.js" as Schedule

Singleton {
    id: root
    property var config: Schedule.normalize({})
    property bool loaded: false
    property bool ready: false
    property bool applied: false
    property string error: ""
    property string storageError: ""
    property double now: Date.now()
    property int sequence: 0
    property int pending: 0
    property string lastSent: ""
    readonly property bool desired: Schedule.effective(config, new Date(now))
    readonly property string overrideLabel: config.scheduled && config.override && config.override.until > now
        ? "Вручную до " + Qt.formatDateTime(new Date(config.override.until), "HH:mm") : ""
    readonly property string status: !ready ? "Нет связи с ночным фильтром"
        : error !== "" ? "Фильтр недоступен" : (applied ? "Включён" : "Выключен")
    readonly property string details: overrideLabel || (config.scheduled
        ? "По расписанию · " + config.start + "–" + config.end : "Ручное управление")

    function send(force) {
        if (!loaded || !socket.connected) return;
        const params = { enabled: desired, temperature: config.temperature };
        const signature = JSON.stringify(params);
        if (!force && lastSent === signature) return;
        pending = ++sequence;
        lastSent = signature;
        socket.write(JSON.stringify({ id: pending, method: "night-light.set", params: params }) + "\n");
        socket.flush();
        responseTimeout.restart();
    }
    function tick() {
        now = Date.now();
        send(false);
    }
    function save(value) {
        try { config = Schedule.normalize(value); }
        catch (failure) { error = "Проверь время и теплоту цвета"; return; }
        now = Date.now();
        storageError = "";
        storage.setText(JSON.stringify(config, null, 2));
        send(true);
    }
    function toggle() {
        now = Date.now();
        const value = Object.assign({}, config);
        // The button describes the actual filter; retry after an asynchronous failure.
        const enabled = ready ? !applied : !desired;
        if (value.scheduled) value.override = { enabled: enabled, until: Schedule.nextBoundary(value, new Date(now)) };
        else value.manual = enabled;
        save(value);
    }
    function setSchedule(enabled) { save(Object.assign({}, config, { scheduled: enabled, override: null })); }
    function setTimes(start, end) { save(Object.assign({}, config, { start: start, end: end, override: null })); }
    function setTemperature(value) { save(Object.assign({}, config, { temperature: Math.round(value) })); }
    function resumeSchedule() { save(Object.assign({}, config, { override: null })); }

    FileView {
        id: storage
        path: Settings.configHome + "/shoji-shell/night-light.json"
        preload: true; printErrors: false; atomicWrites: true
        onLoaded: {
            if (root.loaded) return;
            try { root.config = Schedule.normalize(JSON.parse(text())); }
            catch (failure) { root.storageError = "Не удалось прочитать настройки ночного режима"; }
            root.loaded = true;
            root.tick();
        }
        onLoadFailed: failure => {
            root.loaded = true;
            if (failure !== FileViewError.FileNotFound) root.storageError = "Не удалось загрузить настройки ночного режима";
            root.tick();
        }
        onSaveFailed: root.storageError = "Настройки применены, но не сохранены на диск"
    }
    Socket {
        id: socket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/shojiwm-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        connected: true
        onConnectionStateChanged: {
            root.lastSent = "";
            root.ready = false;
            root.pending = 0;
            responseTimeout.stop();
            if (connected) root.tick();
        }
        parser: SplitParser {
            onRead: data => {
                try {
                    const message = JSON.parse(data);
                    if (message.event === "night-light.changed") {
                        root.ready = true;
                        root.applied = message.payload.enabled;
                        root.error = message.payload.error || "";
                    } else if (message.id === root.pending && root.pending !== 0) {
                        root.pending = 0;
                        responseTimeout.stop();
                        if (message.error) {
                            root.ready = false;
                            root.error = "Примени конфиг ShojiWM: Super+Shift+R";
                        } else {
                            root.ready = true;
                            root.applied = message.result.enabled;
                            root.error = message.result.error || "";
                        }
                    }
                } catch (failure) { root.error = "Не удалось прочитать ответ ночного фильтра"; }
            }
        }
    }
    // Runs independently of whether the control centre is open; catches wake/time changes.
    Timer { interval: 1000; repeat: true; running: root.loaded; onTriggered: root.tick() }
    Timer { interval: 2000; repeat: true; running: !socket.connected; onTriggered: socket.connected = true }
    Timer {
        interval: 10000; repeat: true; running: root.loaded && socket.connected && !root.ready
        onTriggered: root.send(true)
    }
    Timer {
        id: responseTimeout
        interval: 5000
        onTriggered: { root.pending = 0; root.ready = false; root.error = "ShojiWM не ответил на запрос ночного режима"; }
    }
    IpcHandler {
        target: "night-light"
        function toggle(): void { root.toggle(); }
        function status(): string {
            return JSON.stringify({ ready: root.ready, desired: root.desired, applied: root.applied,
                config: root.config, error: root.error, storageError: root.storageError });
        }
    }
}
