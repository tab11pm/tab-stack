pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root
    property bool loaded: false
    property bool enabled: false
    property int minutes: 1
    property string error: ""
    property string storageError: ""
    readonly property bool viewing: Activity.loaded && Activity.viewing && !Activity.manualPaused
    readonly property bool busy: lock.running || suspend.running
    readonly property string status: busy ? "Подготовка ко сну…"
        : enabled && viewing ? "Просмотр · автосон временно приостановлен"
        : enabled ? "Через " + minutes + (minutes === 1 ? " минуту" : " минут") + " бездействия"
        : "Выключен · можно работать без автосна"

    function save() {
        error = "";
        storageError = "";
        saveTimer.restart();
    }
    function toggle() {
        enabled = !enabled;
        save();
    }
    function setMinutes(value) {
        if (!loaded || [1, 5, 10].indexOf(value) < 0 || minutes === value) return;
        minutes = value;
        save();
    }
    function sleepIfIdle() {
        if (!loaded || !enabled || viewing || !monitor.isIdle || busy) return;
        error = "";
        lock.running = true;
    }

    // Coalesce rapid selections so asynchronous writes store the final state.
    Timer {
        id: saveTimer
        interval: 100
        onTriggered: storage.setText(JSON.stringify({ enabled: root.enabled, minutes: root.minutes }, null, 2))
    }

    FileView {
        id: storage
        path: Settings.configHome + "/shoji-shell/idle-sleep.json"
        preload: true; printErrors: false; atomicWrites: true
        onLoaded: {
            if (root.loaded) return;
            try {
                const config = JSON.parse(text());
                if (typeof config.enabled !== "boolean") throw new Error("Invalid setting");
                // Older settings contain only the enabled flag.
                const value = config.minutes === undefined ? 1 : config.minutes;
                if ([1, 5, 10].indexOf(value) < 0) throw new Error("Invalid timeout");
                root.minutes = value;
                root.enabled = config.enabled;
            } catch (failure) {
                // A broken settings file must not unexpectedly enable sleep.
                root.enabled = false;
                root.storageError = "Не удалось прочитать настройки автосна. Включи его кнопкой.";
            }
            root.loaded = true;
        }
        onLoadFailed: failure => {
            if (failure !== FileViewError.FileNotFound) {
                root.enabled = false;
                root.storageError = "Не удалось загрузить настройки автосна";
            }
            root.loaded = true;
        }
        onSaveFailed: root.storageError = "Режим применён, но не сохранён на диск"
    }
    IdleMonitor {
        id: monitor
        enabled: root.loaded && root.enabled && !root.viewing
        timeout: root.minutes * 60
        respectInhibitors: true
        onIsIdleChanged: { if (isIdle) root.sleepIfIdle(); }
    }
    Process {
        id: lock
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("lock/launch.py").toString().replace("file://", ""))]
        stderr: StdioCollector { id: lockDiagnostics; waitForEnd: true }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.error = "Автосон отменён: не удалось заблокировать экран. " + lockDiagnostics.text.trim();
                return;
            }
            // Honour a toggle or fresh input while the locker was starting.
            if (root.enabled && !root.viewing && monitor.isIdle) suspend.running = true;
        }
    }
    Process {
        id: suspend
        command: ["systemctl", "suspend"]
        stderr: StdioCollector { id: suspendDiagnostics; waitForEnd: true }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.error = "Не удалось перейти в спящий режим. " + suspendDiagnostics.text.trim();
        }
    }
}
