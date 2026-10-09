pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "MusicSource.js" as MusicSource

Item {
    id: root
    property bool compact: false
    readonly property alias controlsItem: transport
    implicitWidth: 286
    implicitHeight: compact ? 206 : header.implicitHeight + 20 + transport.implicitHeight + spectrumSurface.height
    width: implicitWidth
    height: implicitHeight

    function sourceName(url) {
        const match = String(url || "").match(/^https:\/\/([^/?#]+)(?:[/?#]|$)/i);
        const host = match ? match[1].toLowerCase().replace(/:443$/, "") : "";
        if (host === "music.yandex.ru") return "Яндекс Музыка";
        if (["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].includes(host)) return "YouTube";
        return host;
    }
    property string selectedPlayerName: ""
    readonly property var player: MusicSource.selectPlayer(Mpris.players.values, capturePid, mateEngine, ambiguousAudio, selectedPlayerName)
    onPlayerChanged: {
        Qt.callLater(() => { if (root.player) root.selectedPlayerName = root.player.dbusName; });
        updatePosition();
    }
    readonly property string source: player ? sourceName(player.metadata["xesam:url"]) || player.identity
        : playing && mateEngine ? "MateEngine" : ""
    readonly property bool playing: player ? player.isPlaying : captureWanted && spectrumAvailable && capturePid > 1 && !ambiguousAudio
        && (!mateEngine || mateTrack.playing === true || rawEnergy > 0.08)
    property real position: 0
    readonly property real length: player && player.lengthSupported ? player.length : 0
    function updatePosition() { position = player && player.positionSupported ? player.position : 0; }
    function seek(fraction) {
        if (!player || !player.canSeek || !player.positionSupported || length <= 0) return;
        player.position = Math.max(0, Math.min(1, fraction)) * length;
        updatePosition();
    }
    Connections {
        target: root.player
        function onTrackChanged() { root.updatePosition(); }
        function onPositionChanged() { root.updatePosition(); }
    }
    Timer { interval: 1000; repeat: true; running: root.visible && root.player !== null && root.playing; triggeredOnStart: true; onTriggered: root.updatePosition() }
    property int capturePid: 0
    property string captureSource: ""
    readonly property bool mateEngine: captureSource === "mateengine"
    property var mateTrack: ({})
    readonly property string mateIcon: Qt.resolvedUrl("icons/mateengine.svg").toString()
    property bool ambiguousAudio: false
    readonly property string title: player ? player.trackTitle || source
        : ambiguousAudio ? "Несколько аудиопотоков" : playing ? (mateEngine ? (mateTrack.playing && mateTrack.title || "MateEngine") : "Звук браузера") : "Ничего не играет"
    readonly property string artist: player ? player.trackArtist || source
        : ambiguousAudio ? "Источник неоднозначен" : playing ? (mateEngine ? (mateTrack.playing && mateTrack.artist || "MateEngine") : "Без данных о треке") : "Включи музыку"
    readonly property string artwork: player ? player.trackArtUrl : mateEngine && playing ? (mateTrack.playing && mateTrack.artwork || mateIcon) : ""
    property var levels: []
    property bool spectrumAvailable: false
    // MPRIS may remain paused on another tab while Web Audio is already playing.
    readonly property bool captureWanted: visible
    readonly property real rawEnergy: captureWanted && spectrumAvailable
        ? Math.max.apply(Math, [0].concat(levels)) : 0
    readonly property real bass: captureWanted && spectrumAvailable
        ? Math.max.apply(Math, [0].concat(levels.slice(2, 9))) : 0
    property real energy: Math.max(0, (rawEnergy - 0.08) / 0.92)
    property real bassFloor: bass
    property real pulse: Math.min(1, Math.max(0, bass - bassFloor) * 4)
    property real flowTarget: 0
    property real flowPhase: flowTarget
    readonly property real colorStrength: energy * (0.22 + pulse * 0.08)
    Behavior on energy { SmoothedAnimation { duration: 180; velocity: -1 } }
    Behavior on bassFloor { SmoothedAnimation { duration: 650; velocity: -1 } }
    Behavior on pulse { SmoothedAnimation { duration: 120; velocity: -1 } }
    Behavior on flowPhase { SmoothedAnimation { duration: 80; velocity: -1 } }

    // One travelling palette ties the dark backdrop to the brighter spectrum.
    function spectrumColor(offset) {
        return Qt.hsla(0.54 + 0.36 * (0.5 + 0.5 * Math.sin(flowPhase - offset * 2.4)),
            compact ? 0.78 : 0.45 + energy * 0.18, compact ? 0.66 + pulse * 0.06 : 0.72 + pulse * 0.06, 1);
    }
    function spectrumBackground(offset) {
        const tint = spectrumColor(offset);
        return Qt.tint(Qt.darker(Theme.surface, 1.25), Qt.rgba(tint.r, tint.g, tint.b, colorStrength));
    }
    Timer {
        interval: 33
        repeat: true
        running: root.captureWanted && root.spectrumAvailable && root.rawEnergy > 0.08
        property double lastTick: 0
        onRunningChanged: lastTick = Date.now()
        onTriggered: {
            const now = Date.now();
            root.flowTarget += Math.max(0, Math.min(0.1, (now - lastTick) / 1000))
                * (0.25 + root.energy * 1.4 + root.pulse * 1.8);
            lastTick = now;
        }
    }


    function stopSpectrum() {
        spectrum.running = false;
        resetSpectrum();
    }
    function resetSpectrum() {
        levels = [];
        spectrumAvailable = false;
        capturePid = 0;
        captureSource = "";
        mateTrack = ({});
        ambiguousAudio = false;
    }
    onCaptureWantedChanged: { if (!captureWanted) stopSpectrum(); }
    Process {
        id: spectrum
        command: ["python3", Qt.resolvedUrl("music-spectrum.py").toString().replace("file://", ""), "--auto"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const frame = JSON.parse(data);
                    if (!root.captureWanted) return;
                    if (!Number.isInteger(frame.pid) || frame.pid < 0 || typeof frame.ambiguous !== "boolean") return;
                    if (frame.source !== undefined && !["", "browser", "mateengine"].includes(frame.source)) return;
                    if (!Array.isArray(frame.bars) || frame.bars.length !== 24
                        || !frame.bars.every(v => typeof v === "number" && isFinite(v) && v >= 0 && v <= 1)) return;
                    root.levels = frame.bars;
                    root.capturePid = frame.pid;
                    root.captureSource = frame.source || "";
                    root.mateTrack = frame.source === "mateengine" && frame.track && typeof frame.track === "object" ? frame.track : ({});
                    root.ambiguousAudio = frame.ambiguous;
                    root.spectrumAvailable = frame.available === true;
                    spectrumTimeout.restart();
                } catch (error) { root.resetSpectrum(); }
            }
        }
        onExited: root.resetSpectrum()
    }
    Timer { interval: 2000; repeat: true; running: root.captureWanted; triggeredOnStart: true; onTriggered: { if (!spectrum.running) spectrum.running = true; } }
    Timer { id: spectrumTimeout; interval: 3500; onTriggered: root.resetSpectrum() }

    component Grain: Canvas {
        id: grain
        required property real strength
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.beginPath();
            ctx.roundedRect(1, 1, width - 2, height - 2, 9, 9);
            ctx.clip();
            ctx.fillStyle = "white";
            ctx.globalAlpha = grain.strength;
            let seed = 173;
            for (let i = 0; i < Math.floor(width * height / 3); i++) {
                seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
                const x = Math.floor(seed / 4294967296 * width);
                seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
                ctx.fillRect(x, Math.floor(seed / 4294967296 * height), 1, 1);
            }
        }
    }
    RowLayout {
        id: header
        visible: !root.compact
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 14
        Rectangle {
            Layout.preferredWidth: root.compact ? 48 : 64; Layout.preferredHeight: root.compact ? 48 : 64
            Layout.alignment: Qt.AlignVCenter
            radius: 4; color: Theme.raised
            Image { id: cover; anchors.fill: parent; source: root.artwork; asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize.width: 128; sourceSize.height: 128 }
            Image { anchors.fill: parent; anchors.margins: 8; source: root.mateIcon; fillMode: Image.PreserveAspectFit; visible: root.mateEngine && cover.status !== Image.Ready }
            PanelIcon { anchors.centerIn: parent; name: "headphones"; tint: Theme.muted; visible: !root.mateEngine && cover.status !== Image.Ready }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "black"
                shadowOpacity: 1
                shadowVerticalOffset: 2
                shadowBlur: 0.8
                blurMax: 8
            }
            UiText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: root.compact ? 16 : 20; font.weight: Font.Bold
                color: "white"
                maximumLineCount: 2; wrapMode: Text.Wrap
                Accessible.name: text
            }
            UiText {
                Layout.fillWidth: true
                text: root.artist
                font.pixelSize: 12
                color: "#f2f2f2"
            }
        }
    }
    ClippingRectangle {
        id: homeCover
        visible: root.compact
        x: 0; y: 0; width: 122; height: 122
        radius: 22; color: Theme.raised
        layer.enabled: root.compact
        layer.effect: MultiEffect {
            shadowEnabled: true; shadowColor: "#080810"; shadowOpacity: 0.6
            shadowVerticalOffset: 4; shadowBlur: 0.8; blurMax: 12
        }
        Image {
            id: homeArtwork
            anchors.fill: parent; source: root.compact ? root.artwork : ""
            asynchronous: true; fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(244, 244)
        }
        Image { anchors.fill: parent; anchors.margins: 16; source: root.mateIcon; fillMode: Image.PreserveAspectFit; visible: root.mateEngine && homeArtwork.status !== Image.Ready }
        PanelIcon { anchors.centerIn: parent; width: 32; height: 32; name: "headphones"; tint: Theme.ink; visible: !root.mateEngine && homeArtwork.status !== Image.Ready }
    }
    WidgetSurface {
        id: homeCard
        visible: root.compact
        x: 52; y: 62; width: root.width - 52; height: root.height - 62
        radius: 20; color: Theme.surface
        border.width: 1; border.color: "#20ffffff"
        Column {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            spacing: 3
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true; shadowColor: "#080810"; shadowOpacity: 1
                shadowVerticalOffset: 2; shadowBlur: 0.7; blurMax: 8
            }
            UiText {
                width: parent.width; text: root.title
                font.pixelSize: 17; font.weight: Font.Bold; color: "white"
                maximumLineCount: 1
                Accessible.name: text
            }
            UiText { width: parent.width; text: root.artist; font.pixelSize: 11; color: "#f2f2f2" }
        }
    }
    Item {
        id: spectrumSurface
        parent: root.compact ? homeCard : root
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: root.compact ? 14 : 0
        anchors.rightMargin: root.compact ? 14 : 0
        anchors.bottomMargin: root.compact ? 12 : 0
        height: root.compact ? 18 : 44
        Rectangle {
            visible: !root.compact
            anchors.fill: parent
            opacity: 0.55
            radius: 10
            color: Qt.darker(Theme.surface, 1.25)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.spectrumBackground(0) }
                GradientStop { position: 0.5; color: root.spectrumBackground(0.5) }
                GradientStop { position: 1; color: root.spectrumBackground(1) }
            }
            border.width: 1
            border.color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.06)
            Grain { strength: 0.045 }
        }
        Item {
            anchors {
                fill: parent
                leftMargin: root.compact ? 0 : 16; rightMargin: root.compact ? 0 : 16
                topMargin: root.compact ? 2 : 10; bottomMargin: root.compact ? 2 : 10
            }
            Accessible.ignored: true
            layer.enabled: root.compact
            layer.effect: MultiEffect {
                shadowEnabled: true; shadowColor: "#080810"; shadowOpacity: 0.9
                shadowVerticalOffset: 2; shadowBlur: 0.6; blurMax: 8
            }
            Row {
                anchors.fill: parent
                spacing: 3
                Repeater {
                    model: 24
                    delegate: Item {
                        required property int index
                        width: (parent.width - 23 * 3) / 24
                        height: parent.height
                        Rectangle {
                            y: root.compact ? (parent.height - height) / 2 : parent.height - height
                            width: parent.width
                            height: Math.max(2, parent.height * (root.levels[index] || 0))
                            radius: root.compact ? width / 2 : 1
                            color: root.captureWanted && root.spectrumAvailable && root.rawEnergy > 0.08
                                ? root.spectrumColor(index / 23) : root.compact ? "#cdd6f4" : Theme.line
                            opacity: root.compact ? 0.90 + root.pulse * 0.10 : 0.4 + root.energy * 0.5 + root.pulse * 0.1
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Behavior on height { NumberAnimation { duration: 75 } }
                        }
                    }
                }
            }
        }
    }
    ColumnLayout {
        id: transport
        parent: root.compact ? homeCard : root
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: root.compact ? 14 : 0
        anchors.rightMargin: root.compact ? 14 : 0
        anchors.bottomMargin: root.compact ? 36 : 54
        spacing: 4
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            Item { Layout.fillWidth: true }
            ActionButton {
                icon.source: Qt.resolvedUrl("icons/previous.svg"); hint: "Предыдущий трек"
                implicitWidth: 32; implicitHeight: 32; padding: 7
                enabled: root.player !== null && root.player.canGoPrevious
                onClicked: { if (root.player && root.player.canGoPrevious) root.player.previous(); }
            }
            ActionButton {
                icon.source: Qt.resolvedUrl(root.playing ? "icons/pause.svg" : "icons/play.svg")
                hint: root.player ? (root.playing ? "Пауза" : "Продолжить воспроизведение") : "Браузер не передаёт управление музыкой"
                implicitWidth: 36; implicitHeight: 32; padding: 7; highlighted: true
                enabled: root.player !== null && root.player.canTogglePlaying
                onClicked: { if (root.player && root.player.canTogglePlaying) root.player.togglePlaying(); }
            }
            ActionButton {
                icon.source: Qt.resolvedUrl("icons/next.svg"); hint: "Следующий трек"
                implicitWidth: 32; implicitHeight: 32; padding: 7
                enabled: root.player !== null && root.player.canGoNext
                onClicked: { if (root.player && root.player.canGoNext) root.player.next(); }
            }
            Item { Layout.fillWidth: true }
        }
        RowLayout {
            visible: root.length > 0
            Layout.fillWidth: true; spacing: 5
            UiText { text: Media.clock(root.position); font.pixelSize: 9; color: Theme.muted }
            PanelSlider {
                Layout.fillWidth: true; implicitHeight: 20
                value: root.length > 0 ? root.position / root.length : 0
                enabled: root.player !== null && root.player.canSeek && root.player.positionSupported
                Accessible.name: "Позиция воспроизведения"
                onMoved: root.seek(value)
            }
            UiText { text: Media.clock(root.length); font.pixelSize: 9; color: Theme.muted }
        }
    }
}
