pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    implicitWidth: 286
    implicitHeight: content.implicitHeight + 32
    width: implicitWidth; height: implicitHeight
    property var account: ({ state: "loading" })
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property bool stale: account.state !== "available"
        || !!account.fetchedAt && clock.date.getTime() - account.fetchedAt > 120000
    function money(value) {
        return typeof value === "number" && isFinite(value)
            ? (account.currency === "CNY" ? "¥" : "$") + value.toFixed(2) : "—";
    }
    Process {
        id: collector
        property bool received: false
        running: Settings.enabled("deepseek")
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("deepseek-widget.py").toString().replace("file://", ""))]
        onStarted: received = false
        stdout: SplitParser {
            onRead: data => {
                try {
                    const value = JSON.parse(data);
                    root.account = ["available", "missing", "auth", "disabled"].includes(value.state)
                        ? value : Object.assign({}, root.account, value);
                    collector.received = true;
                } catch (error) { root.account = Object.assign({}, root.account, { state: "unavailable", error: "DeepSeek недоступен" }); }
            }
        }
        onExited: { if (!received) root.account = Object.assign({}, root.account, { state: "unavailable", error: "DeepSeek недоступен" }); }
    }
    Timer { interval: 60000; running: Settings.enabled("deepseek"); repeat: true; onTriggered: { if (!collector.running) collector.running = true; } }
    WidgetSurface { anchors.fill: parent }
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            UiText { text: "DeepSeek API"; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Rectangle {
                visible: root.stale; implicitWidth: 6; implicitHeight: 6; radius: 3; color: Theme.danger
                Accessible.role: Accessible.Indicator; Accessible.name: "Данные устарели"
            }
        }
        RowLayout {
            Layout.fillWidth: true
            UiText { text: "БАЛАНС"; font.pixelSize: 12; color: Theme.muted; Layout.fillWidth: true }
            UiText { text: root.money(root.account.credit); font.pixelSize: 28; font.weight: Font.Bold; color: "white" }
        }
        RowLayout {
            Layout.fillWidth: true
            UiText { text: "РАСХОД ≈"; font.pixelSize: 12; color: Theme.muted; Layout.fillWidth: true }
            UiText { text: typeof root.account.spent === "number" ? "≈" + root.money(root.account.spent) : "—"; font.pixelSize: 24; font.weight: Font.DemiBold }
        }
        UiText {
            Layout.fillWidth: true; font.pixelSize: 10; color: Theme.muted; wrapMode: Text.Wrap
            text: root.account.error || (root.account.since
                ? "Оценка по снижению баланса с " + Qt.formatDateTime(new Date(root.account.since), "dd.MM HH:mm") + ". Пополнения между проверками могут скрыть расход." : "Ожидание данных")
        }
        ActionButton { text: "Кабинет DeepSeek"; onClicked: Qt.openUrlExternally("https://platform.deepseek.com/usage") }
    }
}
