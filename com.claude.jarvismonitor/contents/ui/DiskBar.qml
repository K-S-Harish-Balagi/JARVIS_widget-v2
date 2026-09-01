import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: diskBar
    spacing: 4

    property string label: ""
    property real percent: 0
    property string detail: ""
    property color barColor: "#4bbed6"

    Behavior on percent {
        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            // Discovered volume names can be long ("238.3 GiB Removable Media"),
            // so the label takes the slack and elides instead of overflowing.
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: diskBar.label
            color: "#c7d3da"
            font.family: "JetBrains Mono"
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1
        }
        Text {
            text: Math.round(diskBar.percent) + "%"
            color: diskBar.barColor
            font.family: "JetBrains Mono"
            font.pixelSize: 11
            font.bold: true
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.08)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(100, diskBar.percent)) / 100
            height: parent.height
            radius: 2
            color: diskBar.barColor
        }
    }

    Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: diskBar.detail
        color: "#8b99a6"
        font.family: "JetBrains Mono"
        font.pixelSize: 9
        font.bold: true
    }
}
