/*
    One volume in the STORAGE panel of page 5: name, how full it is, a bar, and the numbers.
*/
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: diskBar
    spacing: 5

    property string label: ""
    property string kind: ""
    property real percent: 0
    property string detail: ""
    property color barColor: "#89b4fa"

    Behavior on percent {
        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
            // volume names can be long ("238.3 GiB Removable Media"), so this one
            // takes the slack and elides instead of pushing the percentage off
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: diskBar.label
            color: "#cdd6f4"
            font.family: "Inter"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        Text {
            visible: diskBar.kind.length > 0
            text: diskBar.kind
            color: "#7f849c"
            font.family: "Inter"
            font.pixelSize: 11
        }
        Text {
            text: Math.round(diskBar.percent) + "%"
            color: diskBar.barColor
            font.family: "Inter"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 5
        radius: 2.5
        color: Qt.rgba(205 / 255, 214 / 255, 244 / 255, 0.1)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(100, diskBar.percent)) / 100
            height: parent.height
            radius: 2.5
            color: diskBar.barColor
        }
    }

    Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: diskBar.detail
        color: "#7f849c"
        font.family: "JetBrains Mono"
        font.pixelSize: 10
    }
}
