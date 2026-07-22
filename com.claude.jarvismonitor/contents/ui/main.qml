import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation
    Plasmoid.title: "Jarvis Monitor"

    readonly property int hudMinWidth: 800
    readonly property int hudMinHeight: 330
    Layout.minimumWidth: hudMinWidth
    Layout.minimumHeight: hudMinHeight

    Sensors.Sensor { id: ramSensor; sensorId: "memory/physical/usedPercent" }
    Sensors.Sensor { id: ramUsed; sensorId: "memory/physical/used" }
    Sensors.Sensor { id: ramTotal; sensorId: "memory/physical/total" }
    Sensors.Sensor { id: swapSensor; sensorId: "memory/swap/usedPercent" }
    Sensors.Sensor { id: swapUsed; sensorId: "memory/swap/used" }
    Sensors.Sensor { id: swapTotal; sensorId: "memory/swap/total" }
    Sensors.Sensor { id: diskSensor; sensorId: "disk/all/usedPercent" }
    Sensors.Sensor { id: diskUsed; sensorId: "disk/all/used" }
    Sensors.Sensor { id: diskTotal; sensorId: "disk/all/total" }
    Sensors.Sensor { id: diskSystemPercent; sensorId: "disk/d665092e-06be-45a7-949b-97d2bad080b9/usedPercent" }
    Sensors.Sensor { id: diskSystemUsed; sensorId: "disk/d665092e-06be-45a7-949b-97d2bad080b9/used" }
    Sensors.Sensor { id: diskSystemTotal; sensorId: "disk/d665092e-06be-45a7-949b-97d2bad080b9/total" }
    Sensors.Sensor { id: diskDataPercent; sensorId: "disk/06747f57747f4887/usedPercent" }
    Sensors.Sensor { id: diskDataUsed; sensorId: "disk/06747f57747f4887/used" }
    Sensors.Sensor { id: diskDataTotal; sensorId: "disk/06747f57747f4887/total" }

    // DATA is a secondary HDD that mounts a few seconds after plasmashell starts,
    // so the sensor doesn't exist yet when these bindings are first created.
    // Re-set sensorId to force a fresh subscribe until ksystemstats picks it up.
    Timer {
        interval: 4000
        repeat: true
        running: diskDataPercent.status !== Sensors.Sensor.Ready
        onTriggered: {
            const id = "disk/06747f57747f4887"
            diskDataPercent.sensorId = ""
            diskDataUsed.sensorId = ""
            diskDataTotal.sensorId = ""
            diskDataPercent.sensorId = id + "/usedPercent"
            diskDataUsed.sensorId = id + "/used"
            diskDataTotal.sensorId = id + "/total"
        }
    }
    Sensors.Sensor { id: gpuSensor; sensorId: "gpu/all/usage" }
    Sensors.Sensor { id: gpuVramUsed; sensorId: "gpu/all/usedVram" }
    Sensors.Sensor { id: gpuVramTotal; sensorId: "gpu/all/totalVram" }
    Sensors.Sensor { id: netDownSensor; sensorId: "network/all/download" }
    Sensors.Sensor { id: netUpSensor; sensorId: "network/all/upload" }
    Sensors.Sensor { id: batterySensor; sensorId: "power/battery_BAT0/chargePercentage" }
    Sensors.Sensor { id: batteryChargeRateSensor; sensorId: "power/battery_BAT0/chargeRate" }

    // Same startup race as DATA disk above: if ksystemstats' battery source isn't
    // ready yet when this binding is first created, it never resolves. Force a
    // resubscribe until it reports Ready.
    Timer {
        interval: 4000
        repeat: true
        running: batterySensor.status !== Sensors.Sensor.Ready
        onTriggered: {
            batterySensor.sensorId = ""
            batteryChargeRateSensor.sensorId = ""
            batterySensor.sensorId = "power/battery_BAT0/chargePercentage"
            batteryChargeRateSensor.sensorId = "power/battery_BAT0/chargeRate"
        }
    }

    function shortValue(sensor) {
        return sensor.formattedValue || "—"
    }

    property color accent: Plasmoid.configuration.accentColor
    property color bracketColor: Qt.rgba(accent.r, accent.g, accent.b, 0.55)

    fullRepresentation: Item {
        id: hud
        implicitWidth: root.hudMinWidth
        implicitHeight: root.hudMinHeight
        Layout.minimumWidth: root.hudMinWidth
        Layout.minimumHeight: root.hudMinHeight
        Layout.preferredWidth: root.hudMinWidth
        Layout.preferredHeight: root.hudMinHeight

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Qt.rgba(0.055, 0.086, 0.125, 0.6)
            border.color: Qt.rgba(0.29, 0.66, 0.85, 0.28)
            border.width: 1
        }

        // holographic grid backdrop
        Canvas {
            id: hudGrid
            anchors.fill: parent
            visible: Plasmoid.configuration.showEffects
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = "rgba(75,169,222,0.06)"
                ctx.lineWidth = 1
                var step = 26
                for (var x = step; x < width; x += step) {
                    ctx.beginPath()
                    ctx.moveTo(x + 0.5, 0)
                    ctx.lineTo(x + 0.5, height)
                    ctx.stroke()
                }
                for (var y = step; y < height; y += step) {
                    ctx.beginPath()
                    ctx.moveTo(0, y + 0.5)
                    ctx.lineTo(width, y + 0.5)
                    ctx.stroke()
                }
            }
        }

        // corner brackets
        Repeater {
            model: Plasmoid.configuration.showEffects ? 4 : 0
            Item {
                readonly property bool isRight: index === 1 || index === 3
                readonly property bool isBottom: index === 2 || index === 3
                anchors.top: isBottom ? undefined : parent.top
                anchors.bottom: isBottom ? parent.bottom : undefined
                anchors.left: isRight ? undefined : parent.left
                anchors.right: isRight ? parent.right : undefined
                anchors.margins: 6
                width: 16
                height: 16

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.35; duration: 1600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1; duration: 1600; easing.type: Easing.InOutSine }
                }

                Rectangle {
                    width: parent.width; height: 2
                    color: root.bracketColor
                    anchors.top: parent.isBottom ? undefined : parent.top
                    anchors.bottom: parent.isBottom ? parent.bottom : undefined
                }
                Rectangle {
                    width: 2; height: parent.height
                    color: root.bracketColor
                    anchors.left: parent.isRight ? undefined : parent.left
                    anchors.right: parent.isRight ? parent.right : undefined
                }
            }
        }

        // sweeping scan line
        Rectangle {
            id: scanline
            width: parent.width
            height: 46
            visible: Plasmoid.configuration.showEffects
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(0.42, 0.75, 0.95, 0) }
                GradientStop { position: 0.5; color: Qt.rgba(0.42, 0.75, 0.95, 0.10) }
                GradientStop { position: 1.0; color: Qt.rgba(0.42, 0.75, 0.95, 0) }
            }
            y: -height
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { from: -scanline.height; to: hud.height; duration: 5200; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 1400 }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 20

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "SYSTEM MONITOR"
                    color: root.accent
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 3
                }
                Item { Layout.fillWidth: true }
                BatteryIndicator {
                    visible: Plasmoid.configuration.showBattery
                    percent: batterySensor.value || 0
                    charging: (batteryChargeRateSensor.value || 0) > 0
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: 14
                }
                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: "#5fbe8b"
                    Layout.alignment: Qt.AlignVCenter

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.3; duration: 900 }
                        NumberAnimation { from: 0.3; to: 1; duration: 900 }
                    }
                }
                Text {
                    text: "LIVE"
                    color: "#93a2ac"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                    font.bold: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: Plasmoid.configuration.coreCount
                    delegate: ArcGauge {
                        id: coreGauge
                        label: "C" + (index + 1)
                        ringColor: "#43b4e8"
                        ringSize: 56
                        thickness: 4
                        valueFontSize: 11
                        labelFontSize: 8
                        showDetail: false
                        implicitWidth: 84
                        implicitHeight: 76

                        Sensors.Sensor { id: coreSensor; sensorId: "cpu/cpu" + index + "/usage" }
                        value: coreSensor.value || 0
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                ArcGauge {
                    label: "RAM"; value: ramSensor.value || 0; ringColor: "#75aeda"
                    detail: shortValue(ramUsed) + " / " + shortValue(ramTotal)
                }
                ArcGauge {
                    label: "SWAP"; value: swapSensor.value || 0; ringColor: "#8ea3c0"
                    detail: shortValue(swapUsed) + " / " + shortValue(swapTotal)
                }
                ArcGauge {
                    label: "DISK"; value: diskSensor.value || 0; ringColor: "#5e96c7"
                    detail: shortValue(diskUsed) + " / " + shortValue(diskTotal)
                }
                ArcGauge {
                    visible: Plasmoid.configuration.showGpu
                    label: "GPU"; value: gpuSensor.value || 0; ringColor: "#4bbed6"
                    detail: shortValue(gpuVramUsed) + " / " + shortValue(gpuVramTotal)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(1, 1, 1, 0.1)
                visible: Plasmoid.configuration.showNetwork
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: Plasmoid.configuration.showNetwork

                Text {
                    text: "INTERNET"
                    color: "#93a2ac"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 14
                    Text {
                        text: "▼ " + (netDownSensor.formattedValue || "0 B/s")
                        color: root.accent
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: true
                    }
                    Text {
                        text: "▲ " + (netUpSensor.formattedValue || "0 B/s")
                        color: root.accent
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }
            }

            Rectangle {
                Layout.fillHeight: true
                width: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 170
                spacing: 14

                Text {
                    text: "STORAGE"
                    color: root.accent
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 3
                }

                DiskBar {
                    Layout.fillWidth: true
                    label: "SYSTEM"
                    barColor: "#5e96c7"
                    percent: diskSystemPercent.value || 0
                    detail: shortValue(diskSystemUsed) + " / " + shortValue(diskSystemTotal)
                }

                DiskBar {
                    Layout.fillWidth: true
                    label: "DATA"
                    barColor: "#4bbed6"
                    percent: diskDataPercent.value || 0
                    detail: shortValue(diskDataUsed) + " / " + shortValue(diskDataTotal)
                }
            }
        }
    }
}
