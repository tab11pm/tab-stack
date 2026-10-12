pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// MRU window switcher (Alt+Tab), driven by ShojiWM's D-Bus-free IPC.
//
// ShojiWM binds Alt+Tab and broadcasts switcher.next / switcher.previous over
// its socket; Alt release broadcasts switcher.commit. This singleton opens the
// overlay, asks ShojiWM for the current workspace layout over workspaces.get
// (windows carry lastFocusedAt, so MRU order is real), and focuses the chosen
// window with windows.activate.
//
// A singleton because the window list is not per-screen: the overlay is built
// per output but the state and the socket connection are shared.
Singleton {
    id: root

    property bool open: false
    property string targetOutput: ""
    // MRU-ordered, newest first: { id, appId, title, focused, lastFocusedAt,
    // monitor, workspace }.
    property var entries: []
    property int index: -1
    // Selection asked for before the layout arrived (each Alt+Tab tap while the
    // request is in flight). The first tap opens on the previous window.
    property int desiredIndex: 1
    property int pendingGet: 0
    property int sequence: 0
    property string error: ""
    // A quick Alt+Tab: commit arrived before the layout did. Remember it so the
    // activation fires the moment workspaces.get answers.
    property bool commitPending: false

    function send(method, params) {
        if (!socket.connected) return 0;
        const id = ++sequence;
        socket.write(JSON.stringify({ id: id, method: method, params: params || {} }) + "\n");
        socket.flush();
        return id;
    }

    function closeLocal() {
        open = false;
        entries = [];
        index = -1;
        desiredIndex = 1;
        targetOutput = "";
        pendingGet = 0;
        error = "";
        commitPending = false;
    }

    function request() {
        open = true;
        entries = [];
        index = -1;
        desiredIndex = 1;
        targetOutput = "";
        error = "";
        commitPending = false;
        if (socket.connected) pendingGet = send("workspaces.get");
        else socket.connected = true;
    }

    function step(direction) {
        if (!open) {
            request();
            if (direction < 0) desiredIndex = -1;
            return;
        }
        if (entries.length > 0)
            index = (index + direction + entries.length) % entries.length;
        else
            desiredIndex += direction;
    }

    function commit() {
        if (!open) return;
        if (entries.length === 0 && pendingGet !== 0) {
            // The layout is still in flight; activate as soon as it lands.
            commitPending = true;
            return;
        }
        const entry = entries[index];
        if (entry && !entry.focused)
            send("windows.activate", { windowId: entry.id });
        closeLocal();
    }

    function cancel() {
        if (!open) return;
        closeLocal();
    }

    function pick(i) {
        if (!open || i < 0 || i >= entries.length) return;
        index = i;
        commit();
    }

    function build(view) {
        const list = [];
        const monitors = view.monitors || [];
        for (const monitor of monitors) {
            for (const workspace of (monitor.workspaces || [])) {
                for (const window of (workspace.windows || [])) {
                    list.push({
                        id: window.id,
                        appId: window.appId || "",
                        title: window.title || "",
                        focused: window.focused === true,
                        lastFocusedAt: window.lastFocusedAt || 0,
                        monitor: monitor.name,
                        workspace: workspace.index,
                    });
                }
            }
        }
        if (list.length === 0) {
            closeLocal();
            return;
        }
        list.sort((a, b) => b.lastFocusedAt - a.lastFocusedAt);
        entries = list;
        targetOutput = view.currentMonitor || "";
        index = ((desiredIndex % list.length) + list.length) % list.length;
        if (commitPending) {
            commitPending = false;
            commit();
        }
    }

    IpcHandler {
        target: "switcher"
        function next(): void { root.step(1); }
        function previous(): void { root.step(-1); }
        function commit(): void { root.commit(); }
        function cancel(): void { root.cancel(); }
        function status(): string {
            return JSON.stringify({ open: root.open, output: root.targetOutput,
                index: root.index, count: root.entries.length, error: root.error });
        }
    }

    Socket {
        id: socket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/shojiwm-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        connected: true
        onConnectionStateChanged: {
            if (connected) {
                if (root.open && root.entries.length === 0 && root.pendingGet === 0)
                    root.pendingGet = root.send("workspaces.get");
            } else if (root.open) {
                root.error = "ShojiWM недоступен.";
                root.closeLocal();
            }
        }
        parser: SplitParser {
            onRead: data => {
                try {
                    const message = JSON.parse(data);
                    if (message.event === "switcher.next") {
                        root.step(1);
                    } else if (message.event === "switcher.previous") {
                        root.step(-1);
                    } else if (message.event === "switcher.commit") {
                        root.commit();
                    } else if (message.id === root.pendingGet && root.pendingGet !== 0) {
                        root.pendingGet = 0;
                        root.build(message.result || {});
                    } else if (message.error && root.open) {
                        root.error = String(message.error);
                    }
                } catch (failure) {
                    if (root.open) root.error = "Не удалось прочитать ответ ShojiWM.";
                    console.warn("Window switcher:", failure);
                }
            }
        }
    }
    Timer { interval: 1000; repeat: true; running: !socket.connected; onTriggered: socket.connected = true }
}
