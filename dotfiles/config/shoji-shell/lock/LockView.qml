pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import ".." as Desktop
import "../NightLightSchedule.js" as NightSchedule

Rectangle {
    id: root
    color: Desktop.Theme.surface
    property string userName: Quickshell.env("USER")
    property string backgroundUrl: ""
    property string errorMessage: ""
    property string layoutName: ""
    property bool busy: false
    property bool inputEnabled: true
    property int clearSerial: 0
    property bool preview: false
    property bool capsLock: false
    property string passwordText: ""
    signal passwordEdited(string password)
    signal submitted(string password)

    function focusPassword() { if (inputEnabled && !busy) password.forceActiveFocus(); }
    function syncPassword() {
        // Do not touch the active field if it already contains the shared value:
        // this preserves its cursor/selection and never moves keyboard focus.
        if (password.text !== passwordText) password.text = passwordText;
    }
    function clearPassword() { password.clear(); passwordEdited(""); }
    onPasswordTextChanged: syncPassword()
    onInputEnabledChanged: { if (inputEnabled) Qt.callLater(focusPassword); }
    onBusyChanged: { revealed = false; if (!busy) Qt.callLater(focusPassword); }
    onClearSerialChanged: password.clear()
    Component.onCompleted: { appearance = 1; syncPassword(); Qt.callLater(focusPassword); }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ShojiWM drops its night colour overlay while locked, so the locker tints itself the same way.
    property var nightConfig: null
    readonly property bool nightOn: !!nightConfig && NightSchedule.effective(nightConfig, clock.date)
    FileView {
        path: Desktop.Settings.configHome + "/shoji-shell/night-light.json"
        preload: true; printErrors: false
        onLoaded: { try { root.nightConfig = NightSchedule.normalize(JSON.parse(text())); } catch (failure) { root.nightConfig = null; } }
    }
    // Black-body gains from shojiwm/src/effect/night-color.ts, normalized so 6500 K is neutral.
    function nightGains(kelvin) {
        const t = kelvin / 100;
        const green = (99.4708025861 * Math.log(t) - 161.1195681661) / (99.4708025861 * Math.log(65) - 161.1195681661);
        const blue = (138.5177312231 * Math.log(t - 10) - 305.0447927307) / (138.5177312231 * Math.log(55) - 305.0447927307);
        return Qt.vector3d(1, Math.min(1, green), Math.min(1, blue));
    }
    layer.enabled: nightOn
    layer.effect: ShaderEffect {
        property vector3d gains: root.nightGains(root.nightConfig ? root.nightConfig.temperature : 6500)
        fragmentShader: "../shaders/night-tint.frag.qsb"
    }
    Image {
        anchors.fill: parent
        source: root.backgroundUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(root.width, root.height)
    }
    Rectangle { anchors.fill: parent; color: "#b31e1e2e" }
    MouseArea {
        anchors.fill: parent
        onClicked: root.focusPassword()
    }

    // Presentation adapted from kisa-stack's LockFace.qml; input and PAM stay in SessionLock.
    property real appearance: root.preview || Desktop.Theme.reducedMotion ? 1 : 0
    Behavior on appearance { NumberAnimation { duration: Desktop.Theme.duration(220); easing.type: Easing.OutCubic } }
    property bool revealed: false
    // shortcut: matches grp:alt_shift_toggle in shojiwm input config; read it from settings when the locker can.
    readonly property string layoutShortcut: "Alt+Shift"
    property url avatarUrl: ""
    Process {
        running: true
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("../system-profile.py").toString().replace("file://", ""))]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const profile = JSON.parse(data);
                    if (typeof profile.avatar === "string" && profile.avatar.startsWith("file:///")) root.avatarUrl = profile.avatar;
                } catch (error) { console.warn("Could not read system profile"); }
            }
        }
    }

    ColumnLayout {
        id: clockColumn
        // Narrow outputs drop the clock below the layout badge in the top-right corner.
        anchors { top: parent.top; topMargin: root.width < 560 ? 90 : 48; left: parent.left; right: parent.right; leftMargin: 24; rightMargin: 24 }
        spacing: 12
        visible: root.height >= 520
        opacity: root.appearance
        Desktop.UiText {
            Layout.fillWidth: true
            text: Qt.formatDateTime(clock.date, "hh:mm")
            font.pixelSize: 68
            font.weight: Font.Light
            horizontalAlignment: Text.AlignHCenter
        }
        Desktop.UiText {
            Layout.fillWidth: true
            text: clock.date.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM")
            color: Desktop.Theme.muted
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
        }
    }
    Desktop.WidgetSurface {
        anchors { top: parent.top; right: parent.right; margins: 24 }
        visible: root.layoutName !== ""
        opacity: root.appearance
        width: layoutBadge.implicitWidth + 28
        height: 42
        Accessible.role: Accessible.StaticText
        Accessible.name: "Раскладка: " + root.layoutName + ". Переключение " + root.layoutShortcut
        RowLayout {
            id: layoutBadge
            anchors.centerIn: parent
            spacing: 10
            Desktop.PanelIcon { name: "keyboard"; tint: Desktop.Theme.muted }
            Desktop.UiText { text: root.layoutName; font.pixelSize: 16; font.weight: Font.DemiBold }
            Desktop.UiText { text: root.layoutShortcut; color: Desktop.Theme.muted; font.pixelSize: 11 }
        }
    }

    Item {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(clockColumn.visible ? clockColumn.y + clockColumn.height + 24 : 20, (root.height - height) / 2)
        width: Math.min(420, Math.max(220, root.width - 48))
        height: avatar.height + 20 + form.implicitHeight + 32
        opacity: root.appearance
        Desktop.WidgetSurface { anchors { fill: parent; topMargin: avatar.height / 2 } }
        ClippingRectangle {
            id: avatar
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            width: 96; height: 96
            radius: Desktop.Theme.surfaceRadius
            color: Desktop.Theme.raised
            border.width: 1
            border.color: Qt.rgba(Desktop.Theme.ink.r, Desktop.Theme.ink.g, Desktop.Theme.ink.b, 0.10)
            Image {
                id: portrait
                anchors.fill: parent
                source: root.avatarUrl
                sourceSize: Qt.size(192, 192)
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
            }
            Desktop.UiText {
                anchors.centerIn: parent
                visible: portrait.status !== Image.Ready
                text: root.userName.slice(0, 1).toUpperCase()
                font.pixelSize: 32; font.weight: Font.DemiBold
                color: Desktop.Theme.accent
            }
            Accessible.role: Accessible.Graphic
            Accessible.name: "Аватар: " + root.userName
        }
        ColumnLayout {
            id: form
            anchors { top: avatar.bottom; topMargin: 20; left: parent.left; right: parent.right; leftMargin: 32; rightMargin: 32 }
            spacing: 12
            Desktop.UiText {
                Layout.fillWidth: true
                text: root.userName
                font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
            }
            TextField {
                id: password
                objectName: "lockPasswordInput"
                Layout.fillWidth: true
                implicitHeight: 60
                enabled: root.inputEnabled && !root.busy
                echoMode: root.revealed ? TextInput.Normal : TextInput.Password
                passwordMaskDelay: 0
                passwordCharacter: "●"
                font.family: Desktop.Theme.font
                font.pixelSize: 16
                font.letterSpacing: root.revealed ? 0 : 2
                color: Desktop.Theme.ink
                selectionColor: Desktop.Theme.accent
                selectedTextColor: Desktop.Theme.surface
                leftPadding: 16; rightPadding: 60; topPadding: 24; bottomPadding: 8
                selectByMouse: true
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                Accessible.name: "Пароль пользователя " + root.userName
                background: Rectangle {
                    radius: Desktop.Theme.surfaceRadius
                    color: password.activeFocus ? Desktop.Theme.raised : Qt.rgba(Desktop.Theme.ink.r, Desktop.Theme.ink.g, Desktop.Theme.ink.b, 0.05)
                    border.width: 1
                    border.color: root.errorMessage ? Desktop.Theme.danger
                        : password.activeFocus ? Desktop.Theme.accent : Desktop.Theme.line
                    Behavior on color { ColorAnimation { duration: Desktop.Theme.duration(360) } }
                    Behavior on border.color { ColorAnimation { duration: Desktop.Theme.duration(220) } }
                }
                Desktop.UiText {
                    readonly property bool raised: password.length > 0 || password.activeFocus
                    x: 16; y: raised ? 9 : 20
                    text: "Пароль"
                    font.pixelSize: 16
                    color: Desktop.Theme.muted
                    transformOrigin: Item.TopLeft
                    scale: raised ? 0.8 : 1
                    Behavior on y { NumberAnimation { duration: Desktop.Theme.duration(460); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1] } }
                    Behavior on scale { NumberAnimation { duration: Desktop.Theme.duration(460); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1] } }
                }
                Desktop.ActionButton {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 5 }
                    implicitWidth: 44; implicitHeight: 44; padding: 6
                    focusPolicy: Qt.NoFocus
                    enabled: password.enabled
                    hint: root.revealed ? "Скрыть пароль" : "Показать пароль на этом мониторе"
                    Accessible.checkable: true
                    Accessible.checked: root.revealed
                    contentItem: Desktop.MotionIcon { kind: "eyes"; active: root.revealed; tint: Desktop.Theme.ink }
                    onClicked: { root.revealed = !root.revealed; root.focusPassword(); }
                }
                onActiveFocusChanged: { if (!activeFocus) root.revealed = false; }
                onAccepted: {
                    const value = text;
                    root.clearPassword();
                    root.submitted(value);
                }
                onTextEdited: root.passwordEdited(text)
                Keys.onEscapePressed: root.clearPassword()
                Keys.onPressed: event => {
                    // Qt exposes no portable initial Caps Lock state. Track it
                    // after a printable letter or Caps Lock event on this view.
                    if (event.key === Qt.Key_CapsLock) root.capsLock = !root.capsLock;
                    else if (event.text && event.text.toLowerCase() !== event.text.toUpperCase())
                        root.capsLock = (event.text === event.text.toUpperCase()) !== !!(event.modifiers & Qt.ShiftModifier);
                }
            }
            Desktop.UiText {
                Layout.fillWidth: true
                Layout.minimumHeight: 20
                text: root.errorMessage || (root.busy ? "Проверка пароля…" : root.capsLock ? "Caps Lock включён" : "")
                color: root.errorMessage || root.capsLock ? Desktop.Theme.danger : Desktop.Theme.muted
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                Accessible.role: Accessible.AlertMessage
            }
            Desktop.ActionButton {
                Layout.fillWidth: true
                text: root.busy ? "Проверка…" : "Разблокировать"
                highlighted: true
                focusPolicy: Qt.NoFocus
                enabled: root.inputEnabled && !root.busy && password.length > 0
                onClicked: {
                    const value = password.text;
                    root.clearPassword();
                    root.submitted(value);
                }
            }
        }
    }
    Desktop.UiText {
        anchors { bottom: parent.bottom; bottomMargin: 24; horizontalCenter: parent.horizontalCenter }
        text: root.preview ? "Предпросмотр · экран не заблокирован" : "Сессия заблокирована"
        color: Desktop.Theme.muted
        font.pixelSize: 11
    }
    LockCursor { anchors.fill: parent }
}
