//@ pragma UseQApplication

/*
Jawad's SwayWM status bar

Dependencies:
 * `free`
 * Ripgrep
 * UPower daemon

Adapted from: https://tonybtw.com/tutorial/quickshell/
 */

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.I3
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray

import QtQuick
import QtQuick.Layouts

Variants {
    model: Quickshell.screens.filter(scr => scr.model === 'PL2492Q' || scr.name === 'eDP-1')

    PanelWindow {
        id: root
        required property ShellScreen modelData
        screen: modelData

        // Theme
        property color colBg: "#D9181818"
        property color colFg: "#F0F0F0"

        property color colMuted: "#808080"
        property color colFocus: "#0db9d7"
        property color colActive: "#7aa2f7"

        property color colCpu: "#B0FFD0"
        property color colMem: "#B0FFFF"
        property color colTemp: "#B0D0FF"
        property color colAudio: "#FFB0B0"
        property color colNet: "#FFB080" // feels slightly dark for our colour palette but it works
        property color colBright: "#FFD0B0"

        property string fontFamily: "Roboto"
        property int textSize: 16
        property int uiFontSize: 18

        // System data
        property int cpuUsage: 0
        property int memUsage: 0

        property int cpuTemp: 0
        property int lastCpuIdle: 0
        property int lastCpuTotal: 0

        property int displayBrightness: 0

        property string focusedWinTitle: "Bogos binted? 👽"

        WlrLayershell.namespace: "quickshell-bar-namespace"

        I3IpcListener {
            subscriptions: ["window"]
            onIpcEvent: event => {
                try {
                    const payload = JSON.parse(event.data);
                    if (["focus", "title"].includes(payload.change) && payload.container) {
                        root.focusedWinTitle = payload.container.name ?? "Bogos binted? 👽";
                    }
                } catch (e) {
                    console.error("Failed to parse sway window event:", e);
                }
            }
        }

        // CPU Usage
        FileView {
            id: procStat
            path: "/proc/stat"
            blockLoading: true
        }

        // Memory process
        Process {
            id: memProc
            command: ["sh", "-c", "free | rg Mem"]
            stdout: SplitParser {
                onRead: data => {
                    if (!data)
                        return;
                    const parts = data.trim().split(/\s+/);
                    const total = parseInt(parts[1]) || 1;
                    const used = parseInt(parts[2]) || 0;
                    root.memUsage = Math.round(100 * used / total);
                }
            }
            Component.onCompleted: running = true
        }

        // CPU Temperature
        FileView {
            id: sysTemp
            // Might not be ideal to hardcode thermal zone 0 but I would imagine it's
            // guaranteed to be present
            path: "/sys/class/thermal/thermal_zone0/temp"
        }

        // Display Brightness
        FileView {
            id: backlightBrightness
            path: "/sys/class/backlight/amdgpu_bl1/brightness"
        }

        // Max Display Brightness
        FileView {
            id: backlightMaxBrightness
            path: "/sys/class/backlight/amdgpu_bl1/max_brightness"
        }

        property int maxBrightness: parseInt(backlightMaxBrightness.text())

        Timer {
            // interval: 2000
            interval: 1000
            running: true
            repeat: true
            onTriggered: {
                procStat.reload();
                const cpuStat = procStat.text();
                const cpuStatData = cpuStat.trim().split(/\s+/);
                const idle = parseInt(cpuStatData[4]) + parseInt(cpuStatData[5]);
                const total = cpuStatData.slice(1, 8).reduce((a, b) => a + parseInt(b), 0);
                if (root.lastCpuTotal > 0) {
                    root.cpuUsage = Math.round(100 * (1 - (idle - root.lastCpuIdle) / (total - root.lastCpuTotal)));
                }
                root.lastCpuTotal = total;
                root.lastCpuIdle = idle;

                memProc.running = true;

                sysTemp.reload();
                root.cpuTemp = Math.round(parseInt(sysTemp.text()) / 1000);

                backlightBrightness.reload();
                root.displayBrightness = (parseInt(backlightBrightness.text()) / root.maxBrightness) * 100;
            }
        }

        anchors {
            top: true
            left: true
            right: true
        }
        margins {
            top: 5
            left: 5
            right: 5
        }
        implicitHeight: barContents.implicitHeight + barContents.anchors.topMargin + barContents.anchors.bottomMargin
        color: 'transparent'

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: root.colBg
        }

        RowLayout {
            id: barContents
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
                topMargin: 6
                bottomMargin: 6
            }
            spacing: 14

            // Workspaces
            Row {
                spacing: 10
                Repeater {
                    model: 10

                    Text {
                        required property int index
                        property var ws: I3.workspaces.values.find(w => w.num === index + 1)
                        property bool isActive: I3.focusedWorkspace?.num === (index + 1)
                        text: index + 1
                        color: isActive ? root.colFocus : (ws ? root.colActive : root.colMuted)
                        font {
                            pixelSize: root.uiFontSize
                            bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: I3.dispatch("workspace " + (parent.index + 1))
                        }
                    }
                }
            }

            Rectangle {
                implicitWidth: 1
                implicitHeight: 16
                color: root.colMuted
            }

            // CPU
            Text {
                textFormat: Text.RichText
                text: `<font face='Font Awesome 7 Free Solid'>\uf2db</font> ${root.cpuUsage}%`
                color: root.colCpu
                font.pixelSize: root.uiFontSize
            }

            // Memory
            Text {
                textFormat: Text.RichText
                text: `<font face='Font Awesome 7 Free Solid'>\uf538</font> ${root.memUsage}%`
                color: root.colMem
                font.pixelSize: root.uiFontSize
            }

            // Temperature
            Text {
                textFormat: Text.RichText
                function thermometer(temp: int): string {
                    if (temp <= 40)
                        return "\uf2cb";
                    else if (temp <= 55)
                        return "\uf2ca";
                    else if (temp <= 70)
                        return "\uf2c9";
                    else if (temp <= 85)
                        return "\uf2c8";
                    else
                        return "\uf2c7";
                }
                text: `<font face='Font Awesome 7 Free Solid'>${thermometer(root.cpuTemp)}</font> ${root.cpuTemp}° C`
                color: root.colTemp
                font.pixelSize: root.uiFontSize
            }

            Rectangle {
                implicitWidth: 1
                implicitHeight: 16
                color: root.colMuted
                visible: systray.count > 0
            }

            // System Tray
            Row {
                spacing: 12

                Repeater {
                id: systray
                    model: SystemTray.items
                    delegate: Item {
                        id: trayItem
                        required property SystemTrayItem modelData

                        implicitWidth: 18
                        implicitHeight: 18

                        Image {
                            id: trayIcon
                            anchors.fill: parent
                            source: modelData.icon
                        }

                        QsMenuAnchor {
                            id: menuAnchor
                            anchor {
                                window: root
                                item: trayIcon
                            }
                            menu: trayItem.modelData.menu
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton && trayItem.modelData.hasMenu)
                                    menuAnchor.open();
                                else
                                    trayItem.modelData.activate();
                            }
                        }
                    }
                }
            }

            Item {
                id: winTitlePlaceholder
                Layout.fillWidth: true
            }

            // Idle Inhibitor
            Text {
                id: idleInhibit
                text: idleInhibitor.enabled ? "\uf06e" : "\uf070"
                color: root.colFg
                font {
                    family: 'Font Awesome 7 Free Solid'
                    pixelSize: root.uiFontSize
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        idleInhibitor.enabled = !idleInhibitor.enabled;
                    }
                }
            }

            // Audio
            Text {
                textFormat: Text.RichText
                PwObjectTracker {
                    objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
                }
                property int sinkVolume: Math.round(Pipewire.defaultAudioSink.audio.volume * 100)
                property int sourceVolume: Math.round(Pipewire.defaultAudioSource.audio.volume * 100)

                function audioIcon(pwNode: PwNodeAudio, volume: int): string {
                    if (pwNode.muted)
                        return "\uf6a9";
                    else if (volume <= 10)
                        return "\uf026";
                    else if (volume < 50)
                        return "\uf027";
                    else
                        return "\uf028";
                }

                text: `<font face='Font Awesome 7 Free Solid'>${audioIcon(Pipewire.defaultAudioSink.audio, sinkVolume)}</font> ${sinkVolume}% <font face='Font Awesome 7 Free Solid'>\uf130</font> ${sourceVolume}%`
                color: root.colAudio
                font.pixelSize: root.uiFontSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
                }
            }

            Text {
                id: network
                property list<Network> connectedNetworks: Networking.devices.values.filter(device => device.connected).reduce((acc, device) => acc.concat(device.networks.values.filter(network => network.connected)), [])
                // property list<Network> connectedNetworks: []
                // nullable
                property Network primaryNetwork: connectedNetworks.find(network => network.device.type == DeviceType.Wired) ?? connectedNetworks[0]
                // property Network primaryNetwork: undefined
                property var connType: primaryNetwork?.device?.type
                // property var connType: DeviceType.None
                // nullable
                property var signalStrength: Math.round((primaryNetwork as WifiNetwork)?.signalStrength * 100)
                function connIcon(connType): string {
                    switch (connType) {
                    case 1:
                        return "\uf1eb";
                    case 2:
                        return "\uf796";
                    default:
                        return "\uf071";
                    }
                }
                textFormat: Text.RichText
                // I have to use `.nmSettings[0].id` because `.name` was just giving the name of the interface
                // for wired connections
                text: `<font face='Font Awesome 7 Free Solid' style='font-size: ${root.uiFontSize}px'>${connIcon(connType)}</font> ` + (primaryNetwork?.name ?? "Disconnected") + (signalStrength ? ` (${signalStrength}%)` : "")
                color: root.colNet
                font.pixelSize: root.textSize
            }

            // Display brightness
            Text {
                id: brightness
                textFormat: Text.RichText
                text: "<font face='Font Awesome 7 Free Solid'>\uf185</font> " + root.displayBrightness + "%"
                color: root.colBright
                font.pixelSize: root.uiFontSize
            }

            Text {
                textFormat: Text.RichText
                property int chargeLevel: Math.round(UPower.displayDevice.percentage * 100)
                function batIcon(level: int): string {
                    if (level <= 25)
                        return "\uf244";
                    if (level <= 50)
                        return "\uf243";
                    if (level <= 75)
                        return "\uf241";
                    else
                        return "\uf240";
                }
                text: `<font face='Font Awesome 7 Free Solid'>${batIcon(chargeLevel)}</font> ${chargeLevel}%`
                color: root.colFg
                font.pixelSize: root.uiFontSize
            }

            // Clock
            Text {
                id: clock

                function formatDate(date: date): string {
                    let suffix;
                    const day = date.getDate();
                    if (day >= 11 && day <= 19) {
                        suffix = "th";
                    } else
                        switch (day % 10) {
                        case 1:
                            suffix = "st";
                            break;
                        case 2:
                            suffix = "nd";
                            break;
                        case 3:
                            suffix = "rd";
                            break;
                        default:
                            suffix = "th";
                            break;
                        }

                    // return Qt.formatDate(date, "ddd d") + suffix + Qt.formatDateTime(date, " MMM - HH:mm");
                    return Qt.formatTime(date, "HH:mm");
                }

                color: root.colFg
                font.pixelSize: root.uiFontSize
                text: formatDate(new Date())

                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: clock.text = parent.formatDate(new Date())
                }
            }

            // Power
            Text {
                id: powerButton
                text: "\uf011"
                color: root.colFg
                font {
                    family: "Font Awesome 7 Free Solid"
                    pixelSize: root.uiFontSize
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: powerMenu.visible = !powerMenu.visible
                }
            }

            PopupWindow {
                id: powerMenu
                anchor {
                    window: root
                    rect {
                        x: root.width - powerMenu.width
                        y: root.height + 5
                    }
                }
                implicitHeight: powerMenuColumn.implicitHeight + powerMenuColumn.anchors.margins * 2
                implicitWidth: powerMenuColumn.implicitWidth + powerMenuColumn.anchors.margins * 2
                grabFocus: true
                visible: false
                color: 'transparent'

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: root.colBg

                    ColumnLayout {
                        id: powerMenuColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        Repeater {
                            model: [
                                {
                                    label: "Shutdown",
                                    icon: "\uf011",
                                    cmd: ["systemctl", "poweroff"]
                                },
                                {
                                    label: "Reboot",
                                    icon: "\uf2ea",
                                    cmd: ["systemctl", "reboot"]
                                },
                                {
                                    label: "Sleep",
                                    icon: "\uf236",
                                    cmd: ["systemctl", "hybrid-sleep"]
                                },
                                {
                                    label: "Hibernate",
                                    icon: "\uf28b",
                                    cmd: ["systemctl", "hibernate"]
                                }
                            ]
                            delegate: Text {
                                required property var modelData
                                textFormat: Text.RichText
                                text: `<font face='Font Awesome 7 Free Solid'>${modelData.icon}</font> ${modelData.label}`
                                color: root.colFg
                                font.pixelSize: root.textSize
                                Layout.fillWidth: true

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        powerMenu.visible = false;
                                        actionProc.command = modelData.cmd;
                                        actionProc.running = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Process {
            id: actionProc
        }

        IdleInhibitor {
            id: idleInhibitor
            window: root
            enabled: false
        }

        Text {
            text: root.focusedWinTitle
            color: root.colFg
            font.pixelSize: root.textSize
            anchors.centerIn: parent
            elide: Text.ElideRight
            width: Math.min(implicitWidth, winTitlePlaceholder.width - 2 * root.textSize)
        }
    }
}
