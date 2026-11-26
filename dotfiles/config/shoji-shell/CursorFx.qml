pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property var modes: [
        { id: "none", title: "Обычный" },
        { id: "blob", title: "Жидкость" },
        { id: "ring", title: "Кольцо" }
    ]
    property string mode: "none"
    property string applied: ""
    property bool loaded: false
    property string error: ""

    function send() {
        if (!loaded || !socket.connected) return;
        socket.write(JSON.stringify({ id: "cursor-fx", method: "cursor-fx.set", params: { mode: mode } }) + "\n");
        socket.flush();
    }
    function setMode(value) {
        mode = value;
        storage.setText(JSON.stringify({ mode: value }));
        send();
    }

    FileView {
        id: storage
        path: Settings.configHome + "/shoji-shell/cursor-fx.json"
        preload: true; printErrors: false; atomicWrites: true
        onLoaded: {
            try { root.mode = JSON.parse(text()).mode || "none"; } catch (failure) { root.error = "Не удалось прочитать настройки курсора"; }
            root.loaded = true;
            root.send();
        }
        onLoadFailed: { root.loaded = true; root.send(); }
        onSaveFailed: root.error = "Настройка применена, но не сохранена на диск"
    }
    Socket {
        id: socket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/shojiwm-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        connected: true
        onConnectionStateChanged: { root.applied = ""; if (connected) root.send(); }
        parser: SplitParser {
            onRead: data => {
                try {
                    const message = JSON.parse(data);
                    const state = message.event === "cursor-fx.changed" ? message.payload : message.result;
                    if (state && state.mode !== undefined) {
                        root.applied = state.mode; root.error = "";
                        if (root.loaded && state.mode !== root.mode) root.send();
                    }
                    else if (message.error) root.error = "Примени конфиг ShojiWM: Super+Shift+R";
                } catch (failure) { root.error = "Не удалось прочитать ответ ShojiWM"; }
            }
        }
    }
    Timer { interval: 2000; repeat: true; running: !socket.connected; onTriggered: socket.connected = true }
    // A reloaded compositor forgets the effect without dropping the socket: ask it, and the reply resends.
    Timer {
        interval: 3000; repeat: true; running: root.loaded && socket.connected
        onTriggered: { socket.write(JSON.stringify({ id: "cursor-fx-get", method: "cursor-fx.get" }) + "\n"); socket.flush(); }
    }
}
