import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_coreCount: coreCountSpin.value
    property alias cfg_showBattery: showBatteryCheck.checked
    property alias cfg_showGpu: showGpuCheck.checked
    property alias cfg_showNetwork: showNetworkCheck.checked
    property alias cfg_showEffects: showEffectsCheck.checked
    property alias cfg_minDiskSizeGiB: minDiskSizeSpin.value
    property color cfg_accentColor

    ColorDialog {
        id: colorDialog
        selectedColor: page.cfg_accentColor
        onAccepted: page.cfg_accentColor = selectedColor
    }

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Appearance")
            Kirigami.FormData.isSection: true
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Accent color:")
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                width: Kirigami.Units.iconSizes.medium
                height: width
                radius: 4
                color: page.cfg_accentColor
                border.color: Kirigami.Theme.disabledTextColor
                border.width: 1
            }

            QQC2.Button {
                text: i18n("Choose…")
                onClicked: colorDialog.open()
            }
        }

        QQC2.CheckBox {
            id: showEffectsCheck
            Kirigami.FormData.label: i18n("Effects:")
            text: i18n("Holographic scan-line and grid animation")
        }

        QQC2.SpinBox {
            id: coreCountSpin
            Kirigami.FormData.label: i18n("CPU core gauges:")
            from: 1
            to: 128
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Sections")
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showBatteryCheck
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("Battery indicator")
        }

        QQC2.CheckBox {
            id: showGpuCheck
            text: i18n("GPU gauge")
        }

        QQC2.CheckBox {
            id: showNetworkCheck
            text: i18n("Network throughput")
        }

        QQC2.SpinBox {
            id: minDiskSizeSpin
            Kirigami.FormData.label: i18n("Hide drives under (GiB):")
            from: 0
            to: 10000
        }
    }
}
