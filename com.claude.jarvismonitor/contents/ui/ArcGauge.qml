import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects

Item {
    id: gauge

    property string label: ""
    property string detail: ""
    property real value: 0
    property color ringColor: "#43b4e8"
    property real thickness: 5
    property real ringSize: 100
    property real valueFontSize: 14
    property real labelFontSize: 9
    property bool showDetail: true

    implicitWidth: 128
    // ringSize(100) + topMargin(6) + labelText(~13) + topMargin(2) + detail text(~13),
    // with a few px to spare. The old value (114) undercounted this by ~20px, so
    // whatever came after a gauge in a layout overlapped its detail text.
    implicitHeight: showDetail ? 136 : 76

    Behavior on value {
        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
    }

    Shape {
        id: shape
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: gauge.ringSize
        height: gauge.ringSize
        antialiasing: true

        ShapePath {
            strokeColor: Qt.rgba(1, 1, 1, 0.08)
            strokeWidth: gauge.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: shape.width / 2
                centerY: shape.height / 2
                radiusX: shape.width / 2 - gauge.thickness
                radiusY: shape.width / 2 - gauge.thickness
                startAngle: -90
                sweepAngle: 359.999
            }
        }

        ShapePath {
            id: valuePath
            strokeColor: gauge.ringColor
            strokeWidth: gauge.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: shape.width / 2
                centerY: shape.height / 2
                radiusX: shape.width / 2 - gauge.thickness
                radiusY: shape.width / 2 - gauge.thickness
                startAngle: -90
                sweepAngle: 359.999 * Math.max(0, Math.min(100, gauge.value)) / 100
            }
        }
    }

    Glow {
        anchors.fill: shape
        source: shape
        radius: 7
        samples: 9
        spread: 0.25
        color: Qt.rgba(gauge.ringColor.r, gauge.ringColor.g, gauge.ringColor.b, 0.55)
    }

    Text {
        anchors.centerIn: shape
        text: Math.round(gauge.value) + "%"
        color: "#e7ecee"
        font.family: "JetBrains Mono"
        font.pixelSize: gauge.valueFontSize
        font.bold: true
    }

    Text {
        id: labelText
        anchors.top: shape.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        text: gauge.label
        color: "#93a2ac"
        font.family: "JetBrains Mono"
        font.pixelSize: gauge.labelFontSize
        font.letterSpacing: 1.5
        font.bold: true
    }

    Text {
        anchors.top: labelText.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: gauge.detail
        visible: gauge.showDetail && gauge.detail.length > 0
        color: "#8b99a6"
        font.family: "JetBrains Mono"
        font.pixelSize: 8
        font.bold: true
        elide: Text.ElideRight
    }
}
