import QtQuick
import QtQuick.Layouts
import QtQml.Models

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

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

    Sensors.Sensor { id: gpuSensor; sensorId: "gpu/all/usage" }
    Sensors.Sensor { id: gpuVramUsed; sensorId: "gpu/all/usedVram" }
    Sensors.Sensor { id: gpuVramTotal; sensorId: "gpu/all/totalVram" }
    Sensors.Sensor { id: netDownSensor; sensorId: "network/all/download" }
    Sensors.Sensor { id: netUpSensor; sensorId: "network/all/upload" }
    Sensors.Sensor { id: batterySensor; sensorId: "power/battery_BAT0/chargePercentage" }
    Sensors.Sensor { id: batteryChargeRateSensor; sensorId: "power/battery_BAT0/chargeRate" }

    // Startup race: if ksystemstats' battery source isn't ready yet when this
    // binding is first created, it never resolves on its own. Force a
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

    // Storage volumes are discovered at runtime rather than hardcoded by UUID, so
    // a drive that appears later — a slow-mounting HDD, a USB stick, an SD card —
    // shows up on its own. SensorTreeModel is the same model the System Monitor
    // app's sensor browser uses; its "Disks" branch holds one node per mounted
    // filesystem alongside the raw physical devices, which rescanDisks() separates.
    property var diskList: []

    // Bumped on every rescan. A Sensor whose volume has been unmounted keeps
    // reporting Ready with its last value forever, so the only way to tell a
    // dead volume from a live one is to make each bar re-subscribe and see
    // whether it comes back (see the delegate's live-latch below).
    property int probeTick: 0

    // Cleanly ejecting a drive makes ksystemstats drop its sensor, but pulling
    // one out while still mounted does not: the sensor lingers and keeps serving
    // its last reading, so re-subscribing still reports Ready and the bar would
    // never disappear. The kernel's own mount table is the only reliable answer,
    // so cross-check every volume against it. Lowercased because sensor ids are
    // lowercase while findmnt prints NTFS/FAT UUIDs in caps.
    property var mountedUuids: []

    P5Support.DataSource {
        id: mountProbe
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            disconnectSource(source)
            const lines = String(data["stdout"] || "").split("\n")
            let seen = []
            for (const line of lines) {
                const uuid = line.trim().toLowerCase()
                if (uuid.length > 0) seen.push(uuid)
            }
            root.mountedUuids = seen
        }

        function refresh() {
            // Skip if the previous run hasn't reported back yet.
            if (connectedSources.length === 0) connectSource("findmnt -rno UUID")
        }
    }

    Sensors.SensorTreeModel { id: sensorTree }
    DelegateModel { id: treeWalker; model: sensorTree; delegate: Item {} }

    function rescanDisks() {
        treeWalker.rootIndex = sensorTree.index(-1, -1)

        let disksIdx = null
        for (let i = 0; i < treeWalker.count; i++) {
            const idx = treeWalker.modelIndex(i)
            if (String(sensorTree.data(idx, Qt.DisplayRole)) === "Disks") {
                disksIdx = idx
                break
            }
        }
        if (!disksIdx) return

        // Snapshot the child indices first: descending into a node to read its
        // leaves moves rootIndex, which invalidates treeWalker's current level.
        treeWalker.rootIndex = disksIdx
        let nodes = []
        for (let j = 0; j < treeWalker.count; j++) {
            const idx = treeWalker.modelIndex(j)
            nodes.push({ idx: idx, name: String(sensorTree.data(idx, Qt.DisplayRole)) })
        }

        let found = []
        for (const node of nodes) {
            treeWalker.rootIndex = node.idx
            let prefix = ""
            for (let m = 0; m < treeWalker.count; m++) {
                const sid = String(sensorTree.data(treeWalker.modelIndex(m),
                                                   Sensors.SensorTreeModel.SensorId))
                if (sid.endsWith("/usedPercent")) {
                    prefix = sid.slice(0, -"/usedPercent".length)
                }
            }
            // Physical devices (sda, nvme0n1) expose no usedPercent at all;
            // "disk/all" is the aggregate the DISK gauge already shows; and
            // "[Group] Disk" is a regex placeholder node, not a real sensor.
            if (!prefix || prefix === "disk/all") continue
            if (!/^disk\/[A-Za-z0-9][A-Za-z0-9._:-]*$/.test(prefix)) continue
            found.push({ id: prefix, name: node.name })
        }
        root.diskList = found
        root.probeTick++
        mountProbe.refresh()
    }

    // The tree gains a node as soon as a volume mounts, but keeps stale ones
    // after unmount, so each bar independently checks that its sensor is live.
    Timer {
        id: rescanDebounce
        interval: 700
        onTriggered: root.rescanDisks()
    }

    Connections {
        target: sensorTree
        function onRowsInserted() { rescanDebounce.restart() }
        function onRowsRemoved() { rescanDebounce.restart() }
        function onModelReset() { rescanDebounce.restart() }
    }

    // Safety net in case a mount lands without the tree signalling a row change.
    Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.rescanDisks()
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

                Repeater {
                    model: root.diskList

                    delegate: DiskBar {
                        id: volume
                        required property int index
                        required property var modelData

                        readonly property var barPalette: ["#5e96c7", "#4bbed6", "#75aeda",
                                                           "#8ea3c0", "#43b4e8"]

                        Sensors.Sensor { id: volPercent; sensorId: volume.modelData.id + "/usedPercent" }
                        Sensors.Sensor { id: volUsed; sensorId: volume.modelData.id + "/used" }
                        Sensors.Sensor { id: volTotal; sensorId: volume.modelData.id + "/total" }
                        // The tree node's display name is still the raw sensor id
                        // in the instant after a volume mounts, so take the label
                        // from this sensor, which resolves to the volume label.
                        Sensors.Sensor { id: volName; sensorId: volume.modelData.id + "/name" }

                        // Re-subscribing is what actually tests whether the volume
                        // is still mounted: a live one returns to Ready almost at
                        // once, a dead one stays stuck at Loading.
                        function resubscribe() {
                            const base = volume.modelData.id
                            volPercent.sensorId = ""
                            volUsed.sensorId = ""
                            volTotal.sensorId = ""
                            volName.sensorId = ""
                            volPercent.sensorId = base + "/usedPercent"
                            volUsed.sensorId = base + "/used"
                            volTotal.sensorId = base + "/total"
                            volName.sensorId = base + "/name"
                        }

                        Connections {
                            target: root
                            function onProbeTickChanged() { volume.resubscribe() }
                        }

                        // Latch rather than binding straight to status, so the
                        // brief Loading dip after each re-subscribe doesn't make
                        // a healthy drive flicker out of the list.
                        property bool live: false
                        readonly property bool ready: volPercent.status === Sensors.Sensor.Ready
                        onReadyChanged: {
                            if (ready) {
                                live = true
                                deadTimer.stop()
                            } else {
                                deadTimer.restart()
                            }
                        }
                        Timer {
                            id: deadTimer
                            interval: 4000
                            onTriggered: volume.live = false
                        }

                        readonly property string uuid: String(volume.modelData.id).replace("disk/", "")
                        // Empty means the first mount probe hasn't returned yet;
                        // don't blank the panel out while waiting for it.
                        readonly property bool mounted: root.mountedUuids.length === 0
                                                        || root.mountedUuids.indexOf(uuid) >= 0

                        Layout.fillWidth: true
                        visible: volume.live && volume.mounted
                                 && (volTotal.value || 0) >= Plasmoid.configuration.minDiskSizeGiB * 1073741824
                        label: String(volName.value || volume.modelData.name).toUpperCase()
                        barColor: barPalette[volume.index % barPalette.length]
                        percent: volPercent.value || 0
                        detail: shortValue(volUsed) + " / " + shortValue(volTotal)
                    }
                }
            }
        }
    }
}
