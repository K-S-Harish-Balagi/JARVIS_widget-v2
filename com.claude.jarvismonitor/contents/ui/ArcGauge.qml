/*
    One ring: value inside, name under it, and the numbers under that.
    Catppuccin Mocha, as drawn on page 5 of the Build Set canvas: a flat track, a rounded
    coloured arc, no glow and no monospaced shouting.
*/
import QtQuick
import QtQuick.Shapes

Item {
    id: gauge

    property string label: ""
    property string detail: ""
    property real value: 0
    property color ringColor: "#cba6f7"
    property real thickness: 5
    property real ringSize: 100
    property real valueFontSize: 14
    property real labelFontSize: 11
    property real detailFontSize: 10
    property bool showDetail: true

    implicitWidth: 128
    implicitHeight: showDetail ? ringSize + 46 : ringSize + 24

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
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Qt.rgba(205 / 255, 214 / 255, 244 / 255, 0.1)
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

    Text {
        anchors.centerIn: shape
        text: Math.round(gauge.value) + (gauge.showDetail ? "%" : "")
        color: "#cdd6f4"
        font.family: "Inter"
        font.pixelSize: gauge.valueFontSize
        font.weight: Font.DemiBold
    }

    Text {
        id: labelText
        anchors.top: shape.bottom
        anchors.topMargin: 7
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: gauge.label
        color: "#a6adc8"
        font.family: "Inter"
        font.pixelSize: gauge.labelFontSize
    }

    Text {
        anchors.top: labelText.bottom
        anchors.topMargin: 3
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: gauge.detail
        visible: gauge.showDetail && gauge.detail.length > 0
        color: "#7f849c"
        font.family: "JetBrains Mono"
        font.pixelSize: gauge.detailFontSize
        elide: Text.ElideRight
    }
}
