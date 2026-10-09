pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: power
    readonly property var battery: UPower.displayDevice
    readonly property bool present: battery !== null && battery.isPresent
    readonly property int percentage: present ? Math.round(battery.percentage * 100) : 0
    readonly property string state: !present ? "Батарея не обнаружена"
        : battery.state === UPowerDeviceState.FullyCharged ? "Полностью заряжена"
        : battery.state === UPowerDeviceState.Charging ? "Заряжается"
        : UPower.onBattery ? "Работа от батареи" : "Подключено питание · зарядка приостановлена"
    readonly property string timeLabel: {
        if (!present) return "";
        const seconds = UPower.onBattery ? battery.timeToEmpty : battery.timeToFull;
        if (seconds <= 0 || battery.state === UPowerDeviceState.FullyCharged) return "";
        const minutes = Math.ceil(seconds / 60);
        return (UPower.onBattery ? "Осталось " : "До полного заряда ")
            + (minutes >= 60 ? Math.floor(minutes / 60) + " ч " : "") + minutes % 60 + " мин";
    }
    property var profiles: []
    property string activeProfile: ""
    property string error: ""
    readonly property bool busy: setter.running
    function label(profile) {
        return profile === "power-saver" ? "Экономия" : profile === "balanced" ? "Баланс" : "Максимум";
    }
    function refresh() { if (!reader.running && !setter.running) reader.running = true; }
    function setProfile(profile) {
        if (busy || profiles.indexOf(profile) < 0) return;
        error = "";
        setter.command = ["powerprofilesctl", "set", profile];
        setter.running = true;
    }
    Process {
        id: reader
        command: ["powerprofilesctl", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const entries = [];
                let active = "";
                for (const line of text.split("\n")) {
                    const match = line.match(/^\s*(\*)?\s*(power-saver|balanced|performance):\s*$/);
                    if (!match) continue;
                    entries.push(match[2]);
                    if (match[1]) active = match[2];
                }
                power.profiles = ["power-saver", "balanced", "performance"].filter(p => entries.indexOf(p) >= 0);
                power.activeProfile = active;
            }
        }
        onExited: code => { if (code !== 0) power.error = "Служба профилей питания недоступна"; }
    }
    Process {
        id: setter
        onExited: code => {
            if (code !== 0) power.error = "Не удалось изменить режим питания";
            power.refresh();
        }
    }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: power.refresh() }
}
