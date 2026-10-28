pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

FocusScope {
    id: root
    signal closeRequested()
    focus: true

    // Keep this list aligned with the bindings in shojiwm/src/index.tsx.
    readonly property var sections: [
        { title: "ЗАПУСК И СИСТЕМА", entries: [
            ["Win + K", "Горячие клавиши"],
            ["Win + Shift + K", "Настройка горячих клавиш"],
            ["Win + Space", "Запуск приложений"],
            ["Win + Enter", "Терминал"],
            ["Win + E", "Файлы"],
            ["Win + L", "Заблокировать экран"],
            ["Win + Shift + R", "Перезагрузить конфигурацию"],
            ["Win + Shift + Q", "Завершить сеанс"],
            ["Win + W", "Обои и виджеты"],
            ["Win + Shift + W", "Эффекты экрана"],
            ["Win + Shift + S", "Снимок области"],
            ["Win + Shift + A", "Снимок всего экрана"]
        ] },
        { title: "ОКНА", entries: [
            ["Win + Q", "Закрыть окно"],
            ["Win + M", "Развернуть или восстановить"],
            ["Win + F", "Полный экран"],
            ["Win + Shift + F", "Полный экран на всех мониторах"],
            ["Win + P", "Закрепить окно"],
            ["Win + S", "Переключить плиточный режим"],
            ["Win + ← / →", "Выбрать соседнее окно"],
            ["Win + Ctrl + ← / →", "Выбрать плитку"],
            ["Win + Shift + ← / →", "Переместить плитку"]
        ] },
        { title: "РАБОЧИЕ СТОЛЫ", entries: [
            ["Alt + 1–4", "Перейти на рабочий стол"],
            ["Win + Ctrl + ↑ / ↓", "Предыдущий или следующий стол"],
            ["Win + Shift + ↑ / ↓", "Переместить окно на соседний стол"]
        ] },
        { title: "ЗВУК И УПРАВЛЕНИЕ", entries: [
            ["Alt + Shift", "Сменить раскладку"],
            ["XF86AudioMute", "Выключить или включить звук"],
            ["XF86AudioRaiseVolume", "Громче"],
            ["XF86AudioLowerVolume", "Тише"]
        ] },
        { title: "ДИАГНОСТИКА", entries: [
            ["Win + Ctrl + Shift + F", "Показать FPS"],
            ["Win + Shift + T", "Профилирование"]
        ] }
    ]

    function filteredRows(query) {
        const needle = query.trim().toLocaleLowerCase();
        const rows = [];
        for (const section of sections) {
            const matches = section.entries.filter(entry =>
                !needle || (entry[0] + " " + entry[1] + " " + section.title).toLocaleLowerCase().includes(needle));
            if (!matches.length) continue;
            rows.push({ heading: true, title: section.title });
            for (const entry of matches) rows.push({ heading: false, keys: entry[0], title: entry[1] });
        }
        return rows;
    }

    property var liveBindings: []
    function activeRows(query) {
        const needle = query.trim().toLocaleLowerCase();
        const groups = ["ЗАПУСК И СИСТЕМА", "ОКНА", "РАБОЧИЕ СТОЛЫ", "ЗВУК И УПРАВЛЕНИЕ", "ДИАГНОСТИКА", "СВОИ КОМАНДЫ"];
        const fixed = [
            { title: "Перезагрузить конфигурацию", category: "ЗАПУСК И СИСТЕМА", shortcut: "Super+Shift+R" },
            { title: "Завершить сеанс", category: "ЗАПУСК И СИСТЕМА", shortcut: "Super+Shift+Q" },
            { title: "Сменить раскладку", category: "ЗВУК И УПРАВЛЕНИЕ", shortcut: "Alt+Shift" }
        ];
        const entries = liveBindings.concat(fixed);
        const rows = [];
        for (const group of groups) {
            const matches = entries.filter(item => item.category === group &&
                (!needle || (item.title + " " + (item.shortcut || "") + " " + group).toLocaleLowerCase().includes(needle)));
            if (!matches.length) continue;
            rows.push({ heading: true, title: group });
            for (const item of matches) rows.push({ heading: false,
                keys: item.shortcut ? String(item.shortcut).split("Super").join("Win").split("+").join(" + ") : "Отключено",
                title: item.title });
        }
        return rows;
    }
    readonly property var rows: liveBindings.length ? activeRows(search.text) : filteredRows(search.text)
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
                    if (reply.id === 1 && Array.isArray(reply.result)) root.liveBindings = reply.result;
                } catch (failure) { console.warn("Could not read ShojiWM shortcuts", failure); }
            }
        }
    }

    Component.onCompleted: search.forceActiveFocus()
    Keys.onEscapePressed: closeRequested()

    Rectangle { anchors.fill: parent; color: "#a9000000" }
    MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }

    GrainSurface {
        id: card
        anchors.centerIn: parent
        width: Math.min(760, root.width - 32)
        height: Math.min(680, root.height - 48)
        radius: 16
        clip: true

        Column {
            anchors { fill: parent; margins: 24 }
            spacing: 16

            Row {
                width: parent.width
                spacing: 12
                Rectangle {
                    width: 38; height: 38; radius: 10
                    color: Theme.raised
                    UiText { anchors.centerIn: parent; text: "⌘"; font.pixelSize: 22; color: Theme.accent }
                }
                Column {
                    width: parent.width - 88
                    spacing: 2
                    UiText { text: "Горячие клавиши"; font.pixelSize: 19; font.weight: Font.DemiBold }
                    UiText { text: "ShojiWM · tab-stack"; color: Theme.muted; font.pixelSize: 11 }
                }
                ActionButton {
                    text: "×"; hint: "Закрыть"
                    implicitWidth: 38; implicitHeight: 38
                    onClicked: root.closeRequested()
                }
            }

            Rectangle {
                width: parent.width; height: 42; radius: 10
                color: Theme.raised
                border.color: search.activeFocus ? Theme.accent : Theme.line
                border.width: 1
                UiText {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "⌕"; font.pixelSize: 20; color: Theme.muted
                }
                TextInput {
                    id: search
                    anchors { left: parent.left; leftMargin: 42; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    color: Theme.ink
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.surface
                    font.family: Theme.font; font.pixelSize: 13
                    focus: true
                    clip: true
                    Keys.onEscapePressed: root.closeRequested()
                    Accessible.name: "Поиск горячих клавиш"
                }
                UiText {
                    anchors { left: parent.left; leftMargin: 42; verticalCenter: parent.verticalCenter }
                    visible: search.text === ""
                    text: "Поиск по сочетанию или действию"
                    color: Theme.muted
                    font.pixelSize: 13
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - 38 - 42 - 32 - 48
                clip: true
                model: root.rows
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    id: row
                    required property int index
                    required property var modelData
                    width: list.width - (list.contentHeight > list.height ? 12 : 0)
                    height: modelData.heading ? 42 : 42
                    Accessible.role: modelData.heading ? Accessible.Heading : Accessible.ListItem
                    Accessible.name: modelData.heading ? modelData.title : modelData.keys + ", " + modelData.title
                    UiText {
                        anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 8 }
                        visible: row.modelData.heading === true
                        text: row.modelData.title
                        color: Theme.accent
                        font.pixelSize: 10; font.weight: Font.DemiBold
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: !row.modelData.heading
                        radius: 8
                        color: row.index % 2 ? Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.035) : "transparent"
                    }
                    UiText {
                        anchors { left: parent.left; leftMargin: 12; right: keyLabel.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        visible: !row.modelData.heading
                        text: row.modelData.title
                        font.pixelSize: 13
                    }
                    Rectangle {
                        id: keyLabel
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        visible: !row.modelData.heading
                        width: Math.min(row.width * 0.5, keyText.implicitWidth + 18)
                        height: 26; radius: 6
                        color: Theme.raised
                        border.width: 1; border.color: Theme.line
                        UiText {
                            id: keyText
                            anchors.centerIn: parent
                            text: row.modelData.keys || ""
                            color: Theme.muted
                            font.family: "monospace"; font.pixelSize: 11
                        }
                    }
                }
                UiText {
                    anchors.centerIn: parent
                    visible: root.rows.length === 0
                    text: "Ничего не найдено"
                    color: Theme.muted; font.pixelSize: 13
                }
            }

            UiText {
                width: parent.width
                text: "Win = Super  ·  Esc — закрыть  ·  Прокрутка — остальные сочетания"
                color: Theme.muted
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
