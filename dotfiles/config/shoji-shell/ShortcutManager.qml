pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

FocusScope {
    id: root
    signal closeRequested()
    focus: true
    property var bindings: []
    property var settings: ({ version: 1, overrides: {}, custom: [] })
    property bool loaded: false
    property bool editorOpen: false
    property string editorId: ""
    property bool editorCustom: false
    property bool capturing: false
    property string error: ""
    property bool pendingReload: false
    property var pendingSettings: null
    property bool saving: false
    property bool writeFailed: false
    readonly property var rows: {
        const currentBindings = bindings;
        const currentSettings = settings;
        return buildRows(search.text);
    }

    function formatKey(shortcut) { return String(shortcut || "").split("Super").join("Win").split("+").join(" + "); }
    function normalize(value) {
        const parts = value.split("+").map(part => part.trim()).filter(Boolean);
        if (parts.length < 1 || parts.length > 5) return "";
        const aliases = { win: "Super", super: "Super", meta: "Super", ctrl: "Ctrl", control: "Ctrl", alt: "Alt", shift: "Shift" };
        const modifiers = [];
        for (const part of parts.slice(0, -1)) {
            const mod = aliases[part.toLowerCase()];
            if (!mod || modifiers.includes(mod)) return "";
            modifiers.push(mod);
        }
        const key = parts[parts.length - 1].length === 1 ? parts[parts.length - 1].toUpperCase() : parts[parts.length - 1];
        const named = ["Space", "Return", "Tab", "Escape", "BackSpace", "Delete", "Insert", "Home", "End", "PageUp", "PageDown", "Left", "Right", "Up", "Down", "Print", "XF86AudioMute", "XF86AudioRaiseVolume", "XF86AudioLowerVolume"];
        if (!/^[A-Z0-9]$/.test(key) && !/^F(?:[1-9]|1[0-9]|2[0-4])$/.test(key) && !named.includes(key)) return "";
        if (parts.length === 1 && !key.startsWith("XF86")) return "";
        return ["Super", "Ctrl", "Alt", "Shift"].filter(mod => modifiers.includes(mod)).concat(key).join("+");
    }
    function effective(system) {
        const overrides = settings.overrides || {};
        return Object.prototype.hasOwnProperty.call(overrides, system.id) ? overrides[system.id] : system.defaultShortcut;
    }
    function allEntries() {
        const system = bindings.filter(item => item.kind === "system").map(item =>
            ({ id: item.id, title: item.title, category: item.category, defaultShortcut: item.defaultShortcut,
               shortcut: ["shortcuts", "shortcut-manager"].includes(item.id) ? item.defaultShortcut : effective(item), kind: "system" }));
        const custom = (settings.custom || []).map(item =>
            ({ id: item.id, title: item.title, category: "СВОИ КОМАНДЫ", shortcut: item.shortcut,
               command: item.command, kind: "custom" }));
        const fixed = [
            { id: "native-reload", title: "Перезагрузить конфигурацию", category: "ЗАПУСК И СИСТЕМА", shortcut: "Super+Shift+R", kind: "fixed" },
            { id: "native-exit", title: "Завершить сеанс", category: "ЗАПУСК И СИСТЕМА", shortcut: "Super+Shift+Q", kind: "fixed" },
            { id: "native-layout", title: "Сменить раскладку", category: "ЗВУК И УПРАВЛЕНИЕ", shortcut: "Alt+Shift", kind: "fixed" }
        ];
        return system.concat(fixed, custom);
    }
    function buildRows(query) {
        const needle = query.trim().toLocaleLowerCase();
        const groups = ["ЗАПУСК И СИСТЕМА", "ОКНА", "РАБОЧИЕ СТОЛЫ", "ЗВУК И УПРАВЛЕНИЕ", "ДИАГНОСТИКА", "СВОИ КОМАНДЫ"];
        const result = [];
        for (const group of groups) {
            const entries = allEntries().filter(item => item.category === group &&
                (!needle || (item.title + " " + formatKey(item.shortcut) + " " + group).toLocaleLowerCase().includes(needle)));
            if (!entries.length) continue;
            result.push({ heading: true, title: group });
            for (const entry of entries) result.push(entry);
        }
        return result;
    }
    function openEditor(entry) {
        editorId = entry ? entry.id : "";
        editorCustom = !entry || entry.kind === "custom";
        titleField.text = entry ? entry.title : "";
        shortcutField.text = entry ? formatKey(entry.shortcut || entry.defaultShortcut) : "";
        commandField.text = entry && entry.kind === "custom" ? entry.command : "";
        error = "";
        editorOpen = true;
        capturing = false;
        shortcutField.forceActiveFocus();
    }
    function persist(next) {
        if (saving) return;
        pendingSettings = next;
        saving = true;
        error = "";
        const serialized = JSON.stringify(next, null, 2) + "\n";
        const cached = storage.text();
        if (cached === serialized && !writeFailed) completeSave();
        else storage.setText(writeFailed && cached === serialized ? serialized + "\n" : serialized);
    }
    function completeSave() {
        if (!saving || !pendingSettings) return;
        settings = pendingSettings;
        pendingSettings = null;
        saving = false;
        writeFailed = false;
        pendingReload = true;
        editorOpen = false;
        search.forceActiveFocus();
    }
    function failSave() {
        pendingSettings = null;
        saving = false;
        writeFailed = true;
        error = "Не удалось сохранить настройки клавиш. Проверь доступ к файлу и повтори.";
    }
    function saveEditor() {
        const combo = normalize(shortcutField.text);
        if (!combo) { error = "Введите сочетание, например Win + Shift + U"; return; }
        if (["Super+K", "Super+Shift+K", "Super+Shift+R", "Super+Shift+Q"].includes(combo) && !["shortcuts", "shortcut-manager"].includes(editorId)) {
            error = "Это сочетание зарезервировано системой"; return;
        }
        if (allEntries().some(item => item.id !== editorId && item.shortcut && normalize(item.shortcut) === combo)) {
            error = "Это сочетание уже используется"; return;
        }
        const next = JSON.parse(JSON.stringify(settings));
        if (editorCustom) {
            const title = titleField.text.trim(), command = commandField.text.trim();
            if (!title || title.length > 80) { error = "Укажите название до 80 символов"; return; }
            if (!command || command.length > 2048) { error = "Укажите команду до 2048 символов"; return; }
            if (editorId) {
                next.custom = next.custom.map(item => item.id === editorId ? { id: item.id, title, shortcut: combo, command } : item);
            } else {
                next.custom.push({ id: "user-" + Date.now() + "-" + Math.floor(Math.random() * 100000), title, shortcut: combo, command });
            }
        } else {
            const original = bindings.find(item => item.id === editorId);
            if (!original || ["shortcuts", "shortcut-manager"].includes(original.id)) { error = "Системное сочетание недоступно"; return; }
            if (normalize(original.defaultShortcut) === combo) delete next.overrides[editorId];
            else next.overrides[editorId] = combo;
        }
        persist(next);
    }
    function removeEditor() {
        const next = JSON.parse(JSON.stringify(settings));
        if (editorCustom) next.custom = next.custom.filter(item => item.id !== editorId);
        else if (!["shortcuts", "shortcut-manager"].includes(editorId)) next.overrides[editorId] = null;
        persist(next);
    }
    function restoreEditor() {
        const original = bindings.find(item => item.id === editorId);
        if (!original) { error = "Системное действие недоступно"; return; }
        const combo = normalize(original.defaultShortcut);
        if (allEntries().some(item => item.id !== editorId && item.shortcut && normalize(item.shortcut) === combo)) {
            error = "Исходное сочетание уже используется"; return;
        }
        const next = JSON.parse(JSON.stringify(settings));
        delete next.overrides[editorId];
        persist(next);
    }
    Component.onCompleted: search.forceActiveFocus()
    Keys.onEscapePressed: { if (editorOpen) { editorOpen = false; search.forceActiveFocus(); } else closeRequested(); }

    FileView {
        id: storage
        path: Settings.configHome + "/shojiwm/shortcuts.json"
        preload: true; printErrors: false; atomicWrites: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data.version === 1 && data.overrides && typeof data.overrides === "object" && !Array.isArray(data.overrides) && Array.isArray(data.custom))
                    root.settings = { version: 1, overrides: data.overrides, custom: data.custom.filter(item => item && typeof item.id === "string" && typeof item.title === "string" && typeof item.shortcut === "string" && typeof item.command === "string") };
                else root.error = "Не удалось прочитать настройки клавиш";
            } catch (failure) { root.error = "Не удалось прочитать настройки клавиш"; }
            root.loaded = true;
        }
        onLoadFailed: failure => {
            root.loaded = true;
            if (failure !== FileViewError.FileNotFound) root.error = "Не удалось загрузить настройки клавиш";
        }
        onSaved: root.completeSave()
        onSaveFailed: root.failSave()
    }
    Socket {
        id: socket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/shojiwm-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        connected: true
        onConnectionStateChanged: {
            if (connected) { write(JSON.stringify({ id: 1, method: "shortcuts.get" }) + "\n"); flush(); }
        }
        parser: SplitParser {
            onRead: data => {
                try {
                    const reply = JSON.parse(data);
                    if (reply.id === 1 && Array.isArray(reply.result)) { root.bindings = reply.result; root.pendingReload = false; }
                    else if (reply.id === 1 && reply.error) root.error = "Меню недоступно. Перезагрузи ShojiWM: Win + Shift + R.";
                } catch (failure) { root.error = "Не удалось прочитать ответ ShojiWM"; }
            }
        }
    }
    Timer { interval: 1500; repeat: true; running: !socket.connected; onTriggered: socket.connected = true }

    Rectangle { anchors.fill: parent; color: "#a9000000" }
    MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }
    GrainSurface {
        anchors.centerIn: parent
        width: Math.min(800, root.width - 32)
        height: Math.min(700, root.height - 48)
        radius: 16; clip: true
        Column {
            anchors { fill: parent; margins: 24 }
            spacing: 14
            Item {
                width: parent.width
                height: closeButton.implicitHeight
                UiText {
                    anchors { left: parent.left; right: closeButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: root.editorOpen ? "Настроить сочетание" : "Настройка горячих клавиш"
                    font.pixelSize: 19; font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                ActionButton {
                    id: closeButton
                    anchors.right: parent.right
                    implicitWidth: root.editorOpen ? 72 : 36
                    text: root.editorOpen ? "Назад" : "×"
                    hint: root.editorOpen ? "Назад" : "Закрыть"
                    onClicked: { if (root.editorOpen) root.editorOpen = false; else root.closeRequested(); }
                }
            }
            UiText { width: parent.width; text: "ShojiWM · tab-stack"; color: Theme.muted; font.pixelSize: 11 }
            Row {
                visible: !root.editorOpen
                width: parent.width; spacing: 10
                TextField {
                    id: search
                    width: parent.width - addButton.width - 10
                    placeholderText: "Поиск по сочетанию или действию"
                    color: Theme.ink; placeholderTextColor: Theme.muted
                    font.family: Theme.font; font.pixelSize: 13
                    background: Rectangle { radius: 10; color: Theme.raised; border.color: search.activeFocus ? Theme.accent : Theme.line }
                    Keys.onEscapePressed: root.closeRequested()
                }
                ActionButton { id: addButton; text: "+"; hint: "Добавить сочетание"; implicitWidth: 36; font.pixelSize: 18; enabled: root.loaded && root.bindings.length > 0; onClicked: root.openEditor(null) }
            }
            ListView {
                id: list
                visible: !root.editorOpen
                width: parent.width; height: parent.height - 190
                clip: true; spacing: 2; model: root.rows
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    id: row
                    required property int index
                    required property var modelData
                    width: list.width - 12; height: 44
                    Accessible.role: modelData.heading ? Accessible.Heading : Accessible.Button
                    Accessible.name: modelData.heading ? modelData.title : modelData.title + ", " + root.formatKey(modelData.shortcut)
                    UiText { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 8 }
                        visible: row.modelData.heading === true; text: row.modelData.title; color: Theme.accent; font.pixelSize: 10; font.weight: Font.DemiBold }
                    Rectangle { anchors.fill: parent; visible: !row.modelData.heading; radius: 8; color: hit.hovered ? Theme.hover : row.index % 2 ? Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.035) : "transparent" }
                    UiText { anchors { left: parent.left; leftMargin: 12; right: keys.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        visible: !row.modelData.heading; text: row.modelData.title; color: row.modelData.shortcut === null ? Theme.muted : Theme.ink; font.pixelSize: 13 }
                    UiText { id: keys; anchors { right: editLabel.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        visible: !row.modelData.heading; text: row.modelData.shortcut === null ? "Отключено" : root.formatKey(row.modelData.shortcut); color: row.modelData.shortcut === null ? Theme.muted : Theme.accent; font.family: "monospace"; font.pixelSize: 11 }
                    UiText {
                        id: editLabel
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        visible: !row.modelData.heading && row.modelData.kind !== "fixed" && !["shortcuts", "shortcut-manager"].includes(row.modelData.id)
                        text: "Изменить"
                        color: Theme.muted
                        font.pixelSize: 11
                    }
                    HoverHandler { id: hit; enabled: !row.modelData.heading }
                    TapHandler { enabled: root.loaded && !row.modelData.heading && row.modelData.kind !== "fixed" && !["shortcuts", "shortcut-manager"].includes(row.modelData.id); onTapped: root.openEditor(row.modelData) }
                }
                UiText { anchors.centerIn: parent; visible: root.rows.length === 0; text: root.bindings.length ? "Ничего не найдено" : "Загрузка сочетаний…"; color: Theme.muted }
            }
            Column {
                visible: root.editorOpen
                width: parent.width; spacing: 12
                UiText { text: root.editorCustom ? "Название" : "Системное действие"; color: Theme.muted }
                TextField { id: titleField; width: parent.width; readOnly: !root.editorCustom; color: Theme.ink; font.family: Theme.font; background: Rectangle { radius: 8; color: Theme.raised; border.color: Theme.line } }
                UiText { text: "Сочетание"; color: Theme.muted }
                Row {
                    width: parent.width; spacing: 10
                    TextField {
                        id: shortcutField
                        width: parent.width - captureButton.width - 10
                        placeholderText: "Win + Shift + U"
                        color: Theme.ink; font.family: Theme.font
                        background: Rectangle { radius: 8; color: Theme.raised; border.color: shortcutField.activeFocus ? Theme.accent : Theme.line }
                        Keys.onPressed: event => {
                            if (!root.capturing) return;
                            event.accepted = true;
                            if (event.key === Qt.Key_Escape) { root.capturing = false; return; }
                            const special = {};
                            special[Qt.Key_Space] = "Space"; special[Qt.Key_Return] = "Return";
                            special[Qt.Key_Tab] = "Tab"; special[Qt.Key_Left] = "Left";
                            special[Qt.Key_Right] = "Right"; special[Qt.Key_Up] = "Up";
                            special[Qt.Key_Down] = "Down"; special[Qt.Key_Delete] = "Delete";
                            special[Qt.Key_Backspace] = "BackSpace";
                            let key = special[event.key] || "";
                            if (!key && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) key = String.fromCharCode(event.key);
                            if (!key && event.key >= Qt.Key_0 && event.key <= Qt.Key_9) key = String.fromCharCode(event.key);
                            if (!key && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F24) key = "F" + (event.key - Qt.Key_F1 + 1);
                            if (!key) return;
                            const parts = [];
                            if (event.modifiers & Qt.MetaModifier) parts.push("Win");
                            if (event.modifiers & Qt.ControlModifier) parts.push("Ctrl");
                            if (event.modifiers & Qt.AltModifier) parts.push("Alt");
                            if (event.modifiers & Qt.ShiftModifier) parts.push("Shift");
                            if (!parts.length) { root.error = "Сочетание должно содержать модификатор"; return; }
                            shortcutField.text = parts.concat(key).join(" + ");
                            root.capturing = false;
                            root.error = "";
                        }
                    }
                    ActionButton { id: captureButton; text: root.capturing ? "Нажми…" : "Записать"; onClicked: { root.capturing = true; shortcutField.forceActiveFocus(); } }
                }
                UiText { text: "Пиши Win, Ctrl, Alt, Shift и клавишу через +"; color: Theme.muted; font.pixelSize: 11 }
                UiText { visible: root.editorCustom; text: "Команда"; color: Theme.muted }
                TextField { id: commandField; visible: root.editorCustom; width: parent.width; placeholderText: "Команда для bash"; color: Theme.ink; font.family: Theme.font; background: Rectangle { radius: 8; color: Theme.raised; border.color: Theme.line } }
                UiText { width: parent.width; visible: root.error !== ""; text: root.error; color: Theme.danger; wrapMode: Text.Wrap; font.pixelSize: 12 }
                Row {
                    spacing: 10
                    ActionButton { visible: root.editorId !== ""; enabled: !root.saving; text: root.editorCustom ? "Удалить" : "Отключить"; onClicked: root.removeEditor() }
                    ActionButton { visible: root.editorId !== "" && !root.editorCustom; enabled: !root.saving; text: "По умолчанию"; onClicked: root.restoreEditor() }
                    ActionButton { text: root.saving ? "Сохранение…" : "Сохранить"; enabled: !root.saving; highlighted: true; onClicked: root.saveEditor() }
                }
            }
            UiText { width: parent.width; visible: root.error !== "" && !root.editorOpen; text: root.error; color: Theme.danger; font.pixelSize: 11; wrapMode: Text.Wrap }
            UiText { width: parent.width; text: root.pendingReload ? "Сохранено. Для применения нажми Win + Shift + R" : "Win = Super · Esc — закрыть"; color: root.pendingReload ? Theme.accent : Theme.muted; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
