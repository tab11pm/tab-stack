pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    implicitWidth: 340
    implicitHeight: content.implicitHeight + 36
    width: implicitWidth; height: implicitHeight

    property var speaker: ({ state: "searching" })
    property string note: ""
    property int elapsed: 0
    property real volume: 50
    property real volumeBeforeMute: 50
    property bool showTracks: false
    property var tracks: []
    readonly property bool online: speaker.state === "online"
    readonly property bool playing: online && !!speaker.playing
    readonly property bool paused: online && !!speaker.paused
    readonly property bool live: online && !!speaker.live
    readonly property bool voice: !!speaker.voice
    readonly property string title: speaker.title || (playing || paused ? "Без названия" : "Ничего не играет")
    readonly property string subtitle: speaker.artist || (online ? "Мой плейлист · ~/Music" : "")
    readonly property string headline: online ? "Подключена · " + speaker.ip
        : speaker.state === "nossh" ? speaker.ip + " · SSH :" + speaker.port + " не отвечает"
        : speaker.state === "missing" ? "Не найдена в сети" : "Ищу колонку…"

    function clock(s) { return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2); }
    function refresh() { if (!finder.running) finder.running = true; }
    function act(action, arg) {
        if (!online || actor.running) return;
        actor.command = ["python3", helper, "ctl", speaker.ip, action, arg === undefined ? "" : String(arg)];
        actor.running = true;
    }
    function togglePlay() { act(playing ? "pause" : paused ? "resume" : "play"); }
    function setMode(mode, on) {
        speaker = Object.assign({}, speaker, { [mode]: on });
        act(mode, on ? "on" : "off");
    }
    function trackTitle(file) {
        const name = file.replace(/\.\w{2,4}$/, "");
        const at = name.indexOf(" - ");
        return at < 0 ? name : name.slice(at + 3);
    }
    function setVolume(v) { volume = Math.round(v); act("volume", volume); }

    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("kolonka-widget.py").toString().replace("file://", ""))

    Process {
        id: finder
        running: true
        command: ["python3", root.helper, "status", root.speaker.ip || ""]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const next = JSON.parse(data);
                    root.speaker = next;
                    root.elapsed = next.elapsed || 0;
                    if (next.volume !== null && next.volume !== undefined && !volumeSlider.pressed && !actor.running) root.volume = next.volume;
                } catch (error) { root.speaker = { state: "missing" }; }
            }
        }
        onExited: { if (root.speaker.state === "searching") root.speaker = { state: "missing" }; }
    }
    // Poll quickly while the speaker answers, slowly while it is being searched for.
    Timer { interval: root.online ? 4000 : 15000; running: true; repeat: true; onTriggered: root.refresh() }
    Timer {
        interval: 1000; running: root.playing; repeat: true
        onTriggered: root.elapsed = Math.min(root.elapsed + 1, root.speaker.total || root.elapsed + 1)
    }

    Process {
        id: lister
        command: ["python3", root.helper, "tracks"]
        stdout: SplitParser { onRead: data => { try { root.tracks = JSON.parse(data); } catch (error) { root.tracks = []; } } }
    }

    Process {
        id: actor
        property string last: ""
        stderr: SplitParser { onRead: data => actor.last = data }
        onStarted: last = ""
        onExited: code => {
            root.note = code === 0 ? "" : "Ошибка: " + (last || "команда не выполнена");
            root.refresh();
        }
    }

    // One round transport button; `big` is the accent play/pause key.
    component RoundButton: Rectangle {
        id: btn
        property string glyph
        property string hint
        property bool big: false
        property bool active: false
        signal clicked()
        implicitWidth: big ? 60 : 44; implicitHeight: implicitWidth; radius: width / 2
        color: big ? (area.containsMouse ? Qt.lighter(Theme.accent, 1.12) : Theme.accent)
            : active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
            : area.containsMouse ? Theme.hover : Theme.raised
        opacity: enabled ? 1 : 0.4
        scale: area.pressed ? 0.93 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 90 } }
        PanelIcon {
            anchors.centerIn: parent
            width: btn.big ? 26 : 20; height: width
            name: btn.glyph; tint: btn.big ? Theme.surface : btn.active ? Theme.accent : Theme.ink
        }
        MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: hint
    }

    component PillButton: Rectangle {
        id: pill
        property string glyph
        property string label
        property bool active: false
        signal clicked()
        implicitHeight: 36; radius: 18
        color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : pillArea.containsMouse ? Theme.hover : Theme.raised
        border.width: 1
        border.color: active ? Theme.accent : "transparent"
        opacity: enabled ? 1 : 0.4
        Behavior on color { ColorAnimation { duration: 120 } }
        Row {
            anchors.centerIn: parent; spacing: 8
            PanelIcon { width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter; name: pill.glyph; tint: pill.active ? Theme.accent : Theme.ink }
            UiText { anchors.verticalCenter: parent.verticalCenter; text: pill.label; font.pixelSize: 12; color: pill.active ? Theme.accent : Theme.ink }
        }
        MouseArea { id: pillArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: label
    }

    WidgetSurface { anchors.fill: parent; radius: 22 }
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 14

        // Header: speaker identity, link state, rescan.
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            Rectangle {
                implicitWidth: 40; implicitHeight: 40; radius: 13; color: Theme.raised
                PanelIcon { anchors.centerIn: parent; width: 22; height: 22; name: "speaker"; tint: root.online ? Theme.accent : Theme.muted }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                UiText { text: "Яндекс Станция"; font.pixelSize: 15; font.weight: Font.DemiBold }
                RowLayout {
                    spacing: 6
                    Rectangle {
                        implicitWidth: 7; implicitHeight: 7; radius: 3.5
                        color: root.online ? "#a6e3a1" : root.speaker.state === "searching" ? Theme.accent : Theme.danger
                        SequentialAnimation on opacity {
                            running: root.speaker.state === "searching" || finder.running; loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                    UiText { Layout.fillWidth: true; text: root.headline; font.pixelSize: 11; color: Theme.muted }
                }
            }
            RoundButton { glyph: "refresh"; hint: "Найти колонку заново"; implicitWidth: 36; enabled: !finder.running; onClicked: root.refresh() }
        }

        // Now playing card.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 118; radius: 18
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, root.playing ? 0.30 : 0.14) }
                GradientStop { position: 1; color: Qt.rgba(0.54, 0.71, 0.98, root.playing ? 0.18 : 0.06) }
            }
            border.width: 1; border.color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.10)
            RowLayout {
                anchors { fill: parent; margins: 14 }
                spacing: 14
                Rectangle {
                    implicitWidth: 90; implicitHeight: 90; radius: 16
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: "#89b4fa" }
                    }
                    opacity: root.online ? 1 : 0.4
                    PanelIcon { anchors.centerIn: parent; width: 38; height: 38; name: "headphones"; tint: Theme.surface; opacity: root.playing ? 0 : 0.9 }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    // Equalizer bars replace the glyph while music plays.
                    Row {
                        anchors.centerIn: parent; spacing: 5; height: 40
                        visible: root.playing
                        Repeater {
                            model: 5
                            delegate: Rectangle {
                                id: bar
                                required property int index
                                width: 6; radius: 3; color: Theme.surface
                                anchors.bottom: parent.bottom
                                height: 10
                                SequentialAnimation on height {
                                    running: root.playing; loops: Animation.Infinite
                                    NumberAnimation { to: 16 + (bar.index * 7) % 24; duration: 320 + bar.index * 70; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 8 + (bar.index * 5) % 10; duration: 380 + bar.index * 55; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 3
                    UiText {
                        text: root.playing ? "ИГРАЕТ" : root.paused ? "ПАУЗА" : root.online ? "ОСТАНОВЛЕНО" : "НЕТ СВЯЗИ"
                        font.pixelSize: 10; font.letterSpacing: 1.4; font.weight: Font.DemiBold
                        color: root.playing ? Theme.accent : Theme.muted
                    }
                    UiText {
                        Layout.fillWidth: true; text: root.title
                        font.pixelSize: 17; font.weight: Font.Bold; color: "white"
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    }
                    UiText { Layout.fillWidth: true; text: root.subtitle; font.pixelSize: 12; color: Theme.muted }
                }
            }
        }

        // Progress (read-only: the speaker's player has no seek command).
        ColumnLayout {
            Layout.fillWidth: true; spacing: 5
            visible: (root.playing || root.paused) && !root.live
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 4; radius: 2
                color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.10)
                Rectangle {
                    height: parent.height; radius: 2; color: Theme.accent
                    width: parent.width * Math.min(1, root.elapsed / Math.max(1, root.speaker.total || 1))
                    Behavior on width { NumberAnimation { duration: 900 } }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                UiText { text: root.clock(root.elapsed); font.pixelSize: 10; color: Theme.muted; Layout.fillWidth: true }
                UiText { text: root.clock(root.speaker.total || 0); font.pixelSize: 10; color: Theme.muted }
            }
        }

        // Transport.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 10
            RoundButton { glyph: "shuffle"; hint: "Случайный порядок"; implicitWidth: 36; enabled: root.online; active: !!root.speaker.random; onClicked: root.setMode("random", !root.speaker.random) }
            RoundButton { glyph: "previous"; hint: "Предыдущий трек"; implicitWidth: 40; enabled: root.online; onClicked: root.act("prev") }
            RoundButton {
                big: true; enabled: root.online
                glyph: root.playing ? "pause" : "play"; hint: root.playing ? "Пауза" : "Играть"
                onClicked: root.togglePlay()
            }
            RoundButton { glyph: "next"; hint: "Следующий трек"; implicitWidth: 40; enabled: root.online; onClicked: root.act("next") }
            RoundButton { glyph: "hud-stop"; hint: "Остановить"; implicitWidth: 36; enabled: root.online && (root.playing || root.paused); onClicked: root.act("stop") }
            RoundButton { glyph: "repeat"; hint: "Повтор"; implicitWidth: 36; enabled: root.online; active: !!root.speaker.repeat; onClicked: root.setMode("repeat", !root.speaker.repeat) }
        }

        // Volume.
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            RoundButton {
                implicitWidth: 36
                glyph: root.volume <= 0 ? "muted" : root.volume < 40 ? "volume-low" : "volume"
                hint: root.volume <= 0 ? "Вернуть звук" : "Выключить звук"; enabled: root.online
                onClicked: {
                    if (root.volume > 0) { root.volumeBeforeMute = root.volume; root.setVolume(0); }
                    else root.setVolume(root.volumeBeforeMute || 50);
                }
            }
            PanelSlider {
                id: volumeSlider
                Layout.fillWidth: true
                enabled: root.online
                from: 0; to: 100; stepSize: 1
                value: root.volume
                onMoved: root.volume = value
                onPressedChanged: { if (!pressed) root.setVolume(value); }
                Accessible.name: "Громкость"
            }
            UiText {
                Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight
                text: Math.round(root.volume) + "%"; font.pixelSize: 12; font.weight: Font.DemiBold
                color: root.online ? Theme.ink : Theme.muted
            }
        }

        PillButton {
            Layout.fillWidth: true
            glyph: "volume"; label: root.live ? "Звук ПК идёт на колонку" : "Вывести звук ПК на колонку"
            active: root.live; enabled: root.online
            onClicked: root.act(root.live ? "stop" : "pc-audio")
        }

        // Extras.
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            PillButton {
                Layout.fillWidth: true
                glyph: root.voice ? "mic" : "mic-off"; label: "Голос"
                active: root.voice
                onClicked: {
                    actor.command = ["python3", root.helper, "ctl", root.speaker.ip || "", root.voice ? "voice-off" : "voice-on", ""];
                    if (!actor.running) actor.running = true;
                }
            }
            PillButton {
                Layout.preferredWidth: 96
                glyph: "list-music"; label: "Треки"; active: root.showTracks; enabled: root.online
                onClicked: { root.showTracks = !root.showTracks; if (root.showTracks) lister.running = true; }
            }
            PillButton {
                Layout.preferredWidth: 80
                glyph: "terminal"; label: "SSH"; enabled: !!root.speaker.ip
                onClicked: Quickshell.execDetached(["xdg-terminal-exec", "ssh", "-p", String(root.speaker.port),
                    "-i", Quickshell.env("HOME") + "/.ssh/id_ed25519", "root@" + root.speaker.ip])
            }
        }
        ListView {
            id: trackList
            visible: root.showTracks
            Layout.fillWidth: true; Layout.preferredHeight: 200
            clip: true; spacing: 2
            model: root.tracks
            delegate: Rectangle {
                id: row
                required property string modelData
                required property int index
                readonly property bool current: (root.playing || root.paused) && root.trackTitle(modelData).toLowerCase() === (root.speaker.title || "").toLowerCase()
                width: ListView.view.width; height: 36; radius: 10
                color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : rowArea.containsMouse ? Theme.hover : "transparent"
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 8
                    UiText { text: row.current ? "▶" : String(row.index + 1); Layout.preferredWidth: 22; font.pixelSize: 11; color: row.current ? Theme.accent : Theme.muted }
                    UiText { Layout.fillWidth: true; text: row.modelData.replace(/\.\w{2,4}$/, ""); font.pixelSize: 12; color: row.current ? Theme.accent : Theme.ink }
                }
                MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.act("track", row.modelData) }
                Accessible.role: Accessible.Button; Accessible.name: "Играть " + modelData
            }
        }
        UiText {
            visible: root.note !== ""
            Layout.fillWidth: true; font.pixelSize: 10; color: Theme.danger; wrapMode: Text.Wrap
            text: root.note
        }
    }
}
