import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property string connector: defaultConnector()
    property bool active: false
    property bool available: false
    property real value: 0
    property string error: ""
    property var buses: ({})
    property var pendingCommand: null
    readonly property bool busy: worker.running
    function defaultConnector() {
        const screens = Quickshell.screens;
        return (screens.find(screen => /^(eDP|LVDS|DSI)-\d/.test(screen.name)) || screens[0] || {}).name || "";
    }
    function query(mode, percentage) {
        if (!connector) return;
        const command = ["python3", Qt.resolvedUrl("brightness.py").toString().replace("file://", ""), mode, connector,
            String(percentage), buses[connector] || ""];
        if (worker.running) { pendingCommand = command; return; }
        worker.command = command;
        worker.running = true;
    }
    onActiveChanged: { if (active) query("get", 0); }
    onConnectorChanged: { available = false; error = ""; if (active) query("get", 0); }
    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            root.buses = ({});
            if (!Quickshell.screens.some(screen => screen.name === root.connector)) root.connector = root.defaultConnector();
            if (root.active) root.query("get", 0);
        }
    }
    Process {
        id: worker
        onExited: {
            if (!root.pendingCommand) return;
            const command = root.pendingCommand;
            root.pendingCommand = null;
            Qt.callLater(() => { worker.command = command; worker.running = true; });
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.available) root.buses[result.connector] = result.bus;
                    else root.buses = ({});
                    if (result.connector && result.connector !== root.connector) {
                        if (root.active) Qt.callLater(() => root.query("get", 0));
                        return;
                    }
                    root.available = result.available;
                    root.value = result.value;
                    root.error = result.error;
                } catch (error) { root.available = false; root.error = "Не удалось прочитать яркость"; }
            }
        }
    }
}
