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

    // ZRAM vs disk-backed swap. ksystemstats' memory/swap/* sensors only give the
    // combined total, so these come from /proc/swaps in the swap probe below.
    property real zramUsedBytes: 0
    property real zramTotalBytes: 0
    property real diskSwapUsedBytes: 0
    property real diskSwapTotalBytes: 0
    readonly property real zramUsedPercent: zramTotalBytes > 0 ? zramUsedBytes / zramTotalBytes * 100 : 0
    readonly property real diskSwapUsedPercent: diskSwapTotalBytes > 0 ? diskSwapUsedBytes / diskSwapTotalBytes * 100 : 0

    Sensors.Sensor { id: gpuSensor; sensorId: "gpu/all/usage" }
    Sensors.Sensor { id: gpuVramUsed; sensorId: "gpu/all/usedVram" }
    Sensors.Sensor { id: gpuVramTotal; sensorId: "gpu/all/totalVram" }
    Sensors.Sensor { id: cpuAllSensor; sensorId: "cpu/all/usage" }
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

    // /proc/swaps lists every swap area with its size and use in KiB:
    //   Filename  Type  Size  Used  Priority
    // /dev/zram* are compressed RAM; everything else (here /swapfile) is on disk.
    // The executable engine runs no shell, so this is a plain `cat`.
    P5Support.DataSource {
        id: swapProbe
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            disconnectSource(source)
            let zUsed = 0, zTotal = 0, dUsed = 0, dTotal = 0
            const lines = String(data["stdout"] || "").split("\n").slice(1)
            for (const line of lines) {
                const f = line.trim().split(/\s+/)
                if (f.length < 4) continue
                const size = Number(f[2]) * 1024, used = Number(f[3]) * 1024
                if (!isFinite(size) || !isFinite(used)) continue
                if (f[0].startsWith("/dev/zram")) { zTotal += size; zUsed += used }
                else { dTotal += size; dUsed += used }
            }
            root.zramUsedBytes = zUsed
            root.zramTotalBytes = zTotal
            root.diskSwapUsedBytes = dUsed
            root.diskSwapTotalBytes = dTotal
        }

        function refresh() {
            if (connectedSources.length === 0)
                connectSource("cat /proc/swaps")
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: swapProbe.refresh()
    }

    // the header's "fedora - up 2 d 22 h": no sensor gives it, so read the two files
    property string hostName: ""
    property string upText: ""

    P5Support.DataSource {
        id: sysProbe
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            disconnectSource(source)
            const out = String(data["stdout"] || "").split("\n")
            root.hostName = (out[0] || "").trim()
            const secs = Number((out[1] || "0").trim().split(" ")[0])
            if (isFinite(secs) && secs > 0) {
                const d = Math.floor(secs / 86400)
                const h = Math.floor((secs % 86400) / 3600)
                const m = Math.floor((secs % 3600) / 60)
                root.upText = d > 0 ? "up " + d + " d " + h + " h"
                                    : (h > 0 ? "up " + h + " h " + m + " m" : "up " + m + " m")
            }
        }

        function refresh() {
            if (connectedSources.length === 0)
                connectSource("sh -c 'hostname; cat /proc/uptime'")
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: sysProbe.refresh()
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


    // Catppuccin Mocha, exactly the card on page 5 of the Build Set canvas
    readonly property color cText: "#cdd6f4"
    readonly property color cSub: "#a6adc8"
    readonly property color cFaint: "#7f849c"
    readonly property color cCard: "#1e1e2e"
    readonly property color cPanel: Qt.rgba(49 / 255, 50 / 255, 68 / 255, 0.55)
    readonly property color cLine: Qt.rgba(205 / 255, 214 / 255, 244 / 255, 0.08)
    readonly property color cGreen: "#a6e3a1"

    component Panel: Rectangle {
        default property alias content: inner.data
        property alias spacing: inner.spacing
        color: root.cPanel
        radius: 12
        implicitHeight: inner.implicitHeight + 26
        implicitWidth: inner.implicitWidth + 28

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
        }
    }

    component PanelTitle: Text {
        color: root.cSub
        font.family: "Inter"
        font.pixelSize: 11
        font.letterSpacing: 0.8
        font.weight: Font.Medium
    }

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
            radius: 16
            color: Qt.rgba(30 / 255, 30 / 255, 46 / 255, 0.94)
            border.color: root.cLine
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // ---- header ------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Canvas {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    onPaint: {
                        const c = getContext("2d")
                        c.reset()
                        c.strokeStyle = root.accent
                        c.lineWidth = 1.8
                        c.lineJoin = "round"
                        c.beginPath()
                        c.moveTo(1, 11)
                        c.lineTo(5, 11)
                        c.lineTo(7, 4)
                        c.lineTo(10, 15)
                        c.lineTo(12.5, 9)
                        c.lineTo(17, 9)
                        c.stroke()
                    }
                }
                Text {
                    text: i18n("System monitor")
                    color: root.cText
                    font.family: "Inter"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    text: root.hostName + (root.upText.length > 0 ? " · " + root.upText : "")
                    color: root.cSub
                    font.family: "Inter"
                    font.pixelSize: 12
                }

                Item { Layout.fillWidth: true }

                // battery pill
                Rectangle {
                    visible: Plasmoid.configuration.showBattery && (batterySensor.value || 0) > 0
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: batteryRow.implicitWidth + 20
                    implicitHeight: 24
                    radius: 12
                    color: Qt.rgba(166 / 255, 227 / 255, 161 / 255, 0.16)

                    RowLayout {
                        id: batteryRow
                        anchors.centerIn: parent
                        spacing: 6

                        Canvas {
                            id: batteryIcon
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 12
                            onPaint: {
                                const c = getContext("2d")
                                c.reset()
                                c.strokeStyle = root.cGreen
                                c.fillStyle = root.cGreen
                                c.lineWidth = 1.3
                                c.strokeRect(0.7, 1.5, 12, 9)
                                c.fillRect(13.4, 4.5, 2, 3)
                                const pct = Math.max(0, Math.min(100, batterySensor.value || 0))
                                c.fillRect(2.2, 3, 9 * pct / 100, 6)
                            }
                            Connections {
                                target: batterySensor
                                function onValueChanged() { batteryIcon.requestPaint() }
                            }
                        }
                        Text {
                            text: Math.round(batterySensor.value || 0) + "%"
                                  + ((batteryChargeRateSensor.value || 0) > 0 ? " · " + i18n("charging") : "")
                            color: root.cGreen
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 7
                    Layout.preferredHeight: 7
                    radius: 3.5
                    color: root.cGreen
                    Layout.alignment: Qt.AlignVCenter
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.3; duration: 900 }
                        NumberAnimation { from: 0.3; to: 1; duration: 900 }
                    }
                }
                Text {
                    text: i18n("Live")
                    color: root.cSub
                    font.family: "Inter"
                    font.pixelSize: 12
                }
            }

            // ---- body --------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                ColumnLayout {
                    Layout.fillHeight: true
                    spacing: 12

                    Panel {
                        Layout.fillWidth: true

                        RowLayout {
                            Layout.fillWidth: true
                            PanelTitle { text: i18n("PROCESSOR") }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(cpuAllSensor.value || 0) + "% " + i18n("average")
                                color: root.cText
                                font.family: "Inter"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: Plasmoid.configuration.coreCount
                                delegate: ArcGauge {
                                    required property int index
                                    label: i18n("Core %1", index + 1)
                                    ringColor: root.accent
                                    ringSize: 46
                                    thickness: 4
                                    valueFontSize: 12
                                    labelFontSize: 11
                                    showDetail: false
                                    implicitWidth: 66

                                    Sensors.Sensor { id: coreSensor; sensorId: "cpu/cpu" + index + "/usage" }
                                    value: coreSensor.value || 0
                                }
                            }
                        }
                    }

                    Panel {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        PanelTitle { text: i18n("MEMORY, DISK AND GRAPHICS") }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6

                            readonly property int ringSize: 62
                            readonly property int boxWidth: 84

                            ArcGauge {
                                label: i18n("RAM"); value: ramSensor.value || 0
                                ringColor: root.severityColor(ramSensor.value || 0, "#89b4fa")
                                detail: shortValue(ramUsed) + " / " + shortValue(ramTotal)
                                ringSize: parent.ringSize; thickness: 4; valueFontSize: 13; detailFontSize: 9
                                implicitWidth: parent.boxWidth
                            }
                            ArcGauge {
                                label: i18n("ZRAM"); value: root.zramUsedPercent
                                ringColor: root.severityColor(root.zramUsedPercent, "#fab387")
                                detail: root.zramTotalBytes > 0
                                        ? root.compactBytes(root.zramUsedBytes) + " / " + root.compactBytes(root.zramTotalBytes)
                                        : "—"
                                ringSize: parent.ringSize; thickness: 4; valueFontSize: 13; detailFontSize: 9
                                implicitWidth: parent.boxWidth
                            }
                            ArcGauge {
                                label: i18n("Swap file"); value: root.diskSwapUsedPercent
                                ringColor: root.severityColor(root.diskSwapUsedPercent, "#94e2d5")
                                detail: root.diskSwapTotalBytes > 0
                                        ? root.compactBytes(root.diskSwapUsedBytes) + " / " + root.compactBytes(root.diskSwapTotalBytes)
                                        : "—"
                                ringSize: parent.ringSize; thickness: 4; valueFontSize: 13; detailFontSize: 9
                                implicitWidth: parent.boxWidth
                            }
                            ArcGauge {
                                label: i18n("Disks"); value: root.internalUsedPercent
                                ringColor: root.severityColor(root.internalUsedPercent, "#89b4fa")
                                detail: root.internalTotalBytes > 0
                                        ? root.compactBytes(root.internalUsedBytes) + " / "
                                          + root.compactBytes(root.internalTotalBytes)
                                        : "—"
                                ringSize: parent.ringSize; thickness: 4; valueFontSize: 13; detailFontSize: 9
                                implicitWidth: parent.boxWidth
                            }
                            ArcGauge {
                                visible: Plasmoid.configuration.showGpu
                                label: i18n("GPU"); value: gpuSensor.value || 0
                                ringColor: root.severityColor(gpuSensor.value || 0, "#cba6f7")
                                detail: shortValue(gpuVramUsed) + " / " + shortValue(gpuVramTotal)
                                ringSize: parent.ringSize; thickness: 4; valueFontSize: 13; detailFontSize: 9
                                implicitWidth: parent.boxWidth
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 200
                    Layout.minimumWidth: 200
                    spacing: 12

                    Panel {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        PanelTitle { text: i18n("STORAGE") }

                        Repeater {
                            model: root.diskList

                            delegate: DiskBar {
                                id: volume
                                required property int index
                                required property var modelData

                                readonly property var barPalette: ["#89b4fa", "#94e2d5", "#a6e3a1",
                                                                   "#cba6f7", "#f9e2af"]

                                Sensors.Sensor { id: volPercent; sensorId: volume.modelData.id + "/usedPercent" }
                                Sensors.Sensor { id: volUsed; sensorId: volume.modelData.id + "/used" }
                                Sensors.Sensor { id: volTotal; sensorId: volume.modelData.id + "/total" }
                                // the tree node's display name is still the raw sensor id in the
                                // instant after a volume mounts, so take the label from this one
                                Sensors.Sensor { id: volName; sensorId: volume.modelData.id + "/name" }

                                // re-subscribing is what actually tests whether the volume is still
                                // mounted: a live one returns to Ready at once, a dead one does not
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

                                // latch rather than binding straight to status, so the brief Loading
                                // dip after each re-subscribe does not flicker a healthy drive out
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
                                // empty means the first mount probe has not returned yet; don't
                                // blank the panel out while waiting for it
                                readonly property bool mounted: root.mountedUuids.length === 0
                                                                || root.mountedUuids.indexOf(uuid) >= 0

                                Layout.fillWidth: true
                                visible: volume.live && volume.mounted
                                         && (volTotal.value || 0) >= Plasmoid.configuration.minDiskSizeGiB * 1073741824
                                label: String(volName.value || volume.modelData.name)
                                kind: root.compactBytes(volTotal.value || 0)
                                barColor: root.severityColor(volPercent.value || 0,
                                                             barPalette[volume.index % barPalette.length])
                                percent: volPercent.value || 0
                                detail: shortValue(volUsed) + " / " + shortValue(volTotal)
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    Panel {
                        Layout.fillWidth: true
                        visible: Plasmoid.configuration.showNetwork

                        PanelTitle { text: i18n("NETWORK") }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14

                            Text {
                                text: "↓ " + (netDownSensor.formattedValue || "0 B/s")
                                color: root.cText
                                font.family: "JetBrains Mono"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "↑ " + (netUpSensor.formattedValue || "0 B/s")
                                color: root.cText
                                font.family: "JetBrains Mono"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }
}
