import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts

RowLayout {
    id: root
    spacing: 9

    property real percent: 0
    property bool charging: false

    readonly property color levelColor: percent > 50 ? "#5fbe8b" : (percent > 20 ? "#e0ae63" : "#e28169")

    Behavior on percent {
        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
    }

    Text {
        text: Math.round(root.percent) + "%"
        color: "#93a2ac"
        font.family: "JetBrains Mono"
        font.pixelSize: 15
        font.bold: true
    }

    Item {
        width: 36
        height: 18
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            id: nub
            width: 3; height: 8
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.35)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
            id: body
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width - nub.width
            radius: 3
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.35)
            border.width: 1.5

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 3
                width: Math.max(0, (parent.width - 6) * Math.max(0, Math.min(100, root.percent)) / 100)
                radius: 1.5
                color: root.levelColor
            }

            Shape {
                id: bolt
                visible: root.charging
                anchors.centerIn: parent
                width: 10.5
                height: 15
                antialiasing: true

                ShapePath {
                    strokeWidth: 1
                    strokeColor: Qt.rgba(0, 0, 0, 0.45)
                    fillColor: "#fff6d6"
                    startX: bolt.width * 0.58; startY: 0
                    PathLine { x: bolt.width * 0.1; y: bolt.height * 0.58 }
                    PathLine { x: bolt.width * 0.42; y: bolt.height * 0.58 }
                    PathLine { x: bolt.width * 0.42; y: bolt.height }
                    PathLine { x: bolt.width; y: bolt.height * 0.4 }
                    PathLine { x: bolt.width * 0.58; y: bolt.height * 0.4 }
                    PathLine { x: bolt.width * 0.58; y: 0 }
                }
            }
        }
    }
}
