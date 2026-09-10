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

    // 486 (wider of the two ring rows) + 36 margins + 40 inter-column spacing +
    // 1 divider + 170 STORAGE = 733, rounded up slightly. This value alone was
    // never the problem, though - Plasma's desktop containment persists an
    // explicit pixel geometry per widget (~/.config/plasma-org.kde.plasma.desktop-
    // appletsrc, ItemGeometries-<res>=Applet-<id>:x,y,w,h) that only grows to
    // meet a larger minimum and never auto-shrinks to match a smaller one - every
    // width cut this session below the stored value was silently a no-op until
    // that stored geometry got updated directly to match.
    readonly property int hudMinWidth: 735
    readonly property int hudMinHeight: 350
    Layout.minimumWidth: hudMinWidth
    Layout.minimumHeight: hudMinHeight

    Sensors.Sensor { id: ramSensor; sensorId: "memory/physical/usedPercent" }
    Sensors.Sensor { id: ramUsed; sensorId: "memory/physical/used" }
    Sensors.Sensor { id: ramTotal; sensorId: "memory/physical/total" }
    Sensors.Sensor { id: swapSensor; sensorId: "memory/swap/usedPercent" }
    Sensors.Sensor { id: swapUsed; sensorId: "memory/swap/used" }
    Sensors.Sensor { id: swapTotal; sensorId: "memory/swap/total" }
    // The DISK gauge deliberately does NOT use ksystemstats' "disk/all", which
    // sums every mounted filesystem — removable media included — and so reads
    // high when a card or USB drive is plugged in. These are totalled from the
    // internal (non-removable) volumes only, in the mount probe below.
    property real internalUsedBytes: 0
    property real internalTotalBytes: 0
    readonly property real internalUsedPercent: internalTotalBytes > 0
                                                ? internalUsedBytes / internalTotalBytes * 100
                                                : 0

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
    // never disappear. The kernel's own block-device table is the only reliable
    // answer, so cross-check every volume against it. Lowercased because sensor
    // ids are lowercase while lsblk prints NTFS/FAT UUIDs in caps.
    property var mountedUuids: []

    P5Support.DataSource {
        id: mountProbe
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            disconnectSource(source)

            let seen = []
            let internal = ({})
            const lines = String(data["stdout"] || "").split("\n")

            for (const line of lines) {
                // -P prints KEY="value" pairs, which stay unambiguous when a
                // field is empty; the plain column output does not.
                let field = ({})
                const pair = /([A-Z]+)="([^"]*)"/g
                let match
                while ((match = pair.exec(line)) !== null) field[match[1]] = match[2]

                const uuid = String(field["UUID"] || "").toLowerCase()
                const mountPoint = String(field["MOUNTPOINT"] || "")
                if (!uuid || !mountPoint || mountPoint === "[SWAP]") continue
                seen.push(uuid)

                // RM=1 marks removable media. Keyed by UUID so a filesystem
                // mounted twice (/ and /home share one here) is counted once.
                if (field["RM"] !== "0" || !field["FSSIZE"]) continue
                internal[uuid] = { total: Number(field["FSSIZE"]),
                                   used: Number(field["FSUSED"] || 0) }
            }

            let totalBytes = 0
            let usedBytes = 0
            for (const uuid in internal) {
                totalBytes += internal[uuid].total
                usedBytes += internal[uuid].used
            }

            root.mountedUuids = seen
            root.internalTotalBytes = totalBytes
            root.internalUsedBytes = usedBytes
        }

        function refresh() {
            // Skip if the previous run hasn't reported back yet.
            if (connectedSources.length === 0)
                connectSource("lsblk -Pnb -o UUID,RM,FSSIZE,FSUSED,MOUNTPOINT")
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

    // Compact "7.2G" style instead of ksysguard's own "7.2 GiB" formattedValue -
    // freeing up real horizontal room in each gauge's detail text (measured: the
    // longest realistic string drops from ~114px to ~72px at the same font size),
    // which is what actually let the ring boxes shrink without eliding.
    function compactBytes(bytes) {
        if (bytes === undefined || bytes === null || isNaN(bytes)) return "—"
        const units = ["B", "K", "M", "G", "T"]
        let v = bytes, i = 0
        while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
        return v.toFixed(1) + units[i]
    }

    function shortValue(sensor) {
        return compactBytes(sensor.value)
    }

    // Capacity metrics (RAM/ZRAM/SWAP/DISK) shift toward amber then red as they
    // fill up, so a problem is visible without reading the number. Deliberately
    // NOT applied to CPU cores or GPU - pegging those at 100% is normal, not bad.
    function severityColor(value, normalColor) {
        if (value >= 90) return "#e28169"
        if (value >= 70) return "#e0ae63"
        return normalColor
    }

    property color accent: Plasmoid.configuration.accentColor
    property color bracketColor: Qt.rgba(accent.r, accent.g, accent.b, 0.8)

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
                width: 26
                height: 26

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.5; duration: 1600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.5; to: 1; duration: 1600; easing.type: Easing.InOutSine }
                }

                Rectangle {
                    width: parent.width; height: 3
                    color: root.bracketColor
                    anchors.top: parent.isBottom ? undefined : parent.top
                    anchors.bottom: parent.isBottom ? parent.bottom : undefined
                }
                Rectangle {
                    width: 3; height: parent.height
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
            height: 64
            visible: Plasmoid.configuration.showEffects
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(0.42, 0.75, 0.95, 0) }
                GradientStop { position: 0.5; color: Qt.rgba(0.42, 0.75, 0.95, 0.22) }
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
                // NOT fillWidth: this column should size to its own content (the wider
                // of the two ring rows), not stretch to fill whatever's left after
                // STORAGE - that elastic stretch was the actual root cause of every
                // "extra gap" in this whole exercise, not a bad width number.
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
                spacing: 6

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
                        // 76 solves 6*76+5*6 = 486 to match the stat row's 5*92+4*6 = 484
                        // below, so the two rows begin AND end at (nearly) the same x -
                        // that's the "alignment" fix, not just a smaller box.
                        implicitWidth: 76
                        implicitHeight: 76

                        Sensors.Sensor { id: coreSensor; sensorId: "cpu/cpu" + index + "/usage" }
                        value: coreSensor.value || 0
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                // Ring shrunk from the original 128/100 default so this row's total width
                // sits closer to the 6-core row above - still clearly bigger than the core
                // rings (82 vs 56), just not by as wide a margin. Box width is sized off the
                // compact detail-text width (see compactBytes above), not the ring itself -
                // that's what actually lets it shrink without eliding.
                readonly property int statRingSize: 82
                // 92 = longest compact detail string ("428.9M / 512.0M" ~ 72px) + padding.
                // 5*92 + 4*6 = 484, matched against the core row's 486 above for alignment.
                readonly property int statBoxWidth: 92
                readonly property int statBoxHeight: 116

                ArcGauge {
                    label: "RAM"; value: ramSensor.value || 0
                    ringColor: root.severityColor(ramSensor.value || 0, "#75aeda")
                    detail: shortValue(ramUsed) + " / " + shortValue(ramTotal)
                    ringSize: parent.statRingSize; thickness: 4
                    valueFontSize: 12; labelFontSize: 8
                    implicitWidth: parent.statBoxWidth; implicitHeight: parent.statBoxHeight
                }
                // Placeholder split of SWAP into ZRAM vs disk-backed swap, just to preview
                // the 5-ring layout. Not wired to real per-device data yet — ksysguard's
                // memory/swap/* sensors only expose the combined total, so a real split
                // would need its own data source (e.g. parsing `swapon --show`).
                ArcGauge {
                    label: "ZRAM"; value: 51
                    ringColor: root.severityColor(51, "#a68cf0")
                    detail: "4.1G / 8.0G"
                    ringSize: parent.statRingSize; thickness: 4
                    valueFontSize: 12; labelFontSize: 8
                    implicitWidth: parent.statBoxWidth; implicitHeight: parent.statBoxHeight
                }
                ArcGauge {
                    label: "SWAP"; value: 11
                    ringColor: root.severityColor(11, "#4ecfa0")
                    detail: "1.7G / 16.0G"
                    ringSize: parent.statRingSize; thickness: 4
                    valueFontSize: 12; labelFontSize: 8
                    implicitWidth: parent.statBoxWidth; implicitHeight: parent.statBoxHeight
                }
                ArcGauge {
                    label: "DISK"; value: root.internalUsedPercent
                    ringColor: root.severityColor(root.internalUsedPercent, "#5e96c7")
                    detail: root.internalTotalBytes > 0
                            ? root.compactBytes(root.internalUsedBytes) + " / "
                              + root.compactBytes(root.internalTotalBytes)
                            : "—"
                    ringSize: parent.statRingSize; thickness: 4
                    valueFontSize: 12; labelFontSize: 8
                    implicitWidth: parent.statBoxWidth; implicitHeight: parent.statBoxHeight
                }
                ArcGauge {
                    visible: Plasmoid.configuration.showGpu
                    label: "GPU"; value: gpuSensor.value || 0; ringColor: "#4bbed6"
                    detail: shortValue(gpuVramUsed) + " / " + shortValue(gpuVramTotal)
                    ringSize: parent.statRingSize; thickness: 4
                    valueFontSize: 12; labelFontSize: 8
                    implicitWidth: parent.statBoxWidth; implicitHeight: parent.statBoxHeight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 2
                color: root.bracketColor
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
                Layout.minimumWidth: 170
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
                        barColor: root.severityColor(volPercent.value || 0,
                                                     barPalette[volume.index % barPalette.length])
                        percent: volPercent.value || 0
                        detail: shortValue(volUsed) + " / " + shortValue(volTotal)
                    }
                }
            }
        }
    }
}
