import QtQuick 2.2
import Sailfish.Silica 1.0
import "../js/radar.js" as R

// Bottom docked settings sheet. mode "map" = map settings,
// mode "source" = radar data source settings (opened from the pulley menu).
DockedPanel {
    id: panel

    property var win
    property string mode: "map"

    width: parent ? parent.width : Screen.width
    height: content.height + 2 * Theme.paddingLarge
    dock: Dock.Bottom

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.08, 0.1, 0.12, 0.94)
    }

    // Swipe down anywhere on the panel that is not an interactive control
    // closes it (controls above this area keep their own touch handling).
    MouseArea {
        anchors.fill: parent
        property real startY: 0
        onPressed: startY = mouse.y
        onReleased: {
            if (mouse.y - startY > Theme.itemSizeMedium)
                panel.open = false;
        }
    }

    Column {
        id: content
        x: Theme.horizontalPageMargin
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.horizontalPageMargin
        spacing: Theme.paddingMedium

        Label {
            text: panel.mode === "source" ? qsTr("Zdroj radaru") : qsTr("Nastavení mapy")
            color: "#4fd1d9"
            font.pixelSize: Theme.fontSizeLarge
        }

        // ---- map settings ----
        Label {
            visible: panel.mode === "map"
            text: qsTr("Typ mapy")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }
        Row {
            visible: panel.mode === "map"
            width: parent.width
            spacing: Theme.paddingSmall
            Button {
                width: (parent.width - 2 * Theme.paddingSmall) / 3
                text: qsTr("Základní")
                color: panel.win.cfg.mapType === "voyager" ? Theme.highlightColor : Theme.primaryColor
                onClicked: panel.win.cfg.mapType = "voyager"
            }
            Button {
                width: (parent.width - 2 * Theme.paddingSmall) / 3
                text: qsTr("Reliéf")
                color: panel.win.cfg.mapType === "relief" ? Theme.highlightColor : Theme.primaryColor
                onClicked: panel.win.cfg.mapType = "relief"
            }
            Button {
                width: (parent.width - 2 * Theme.paddingSmall) / 3
                text: qsTr("Tmavá")
                color: panel.win.cfg.mapType === "dark" ? Theme.highlightColor : Theme.primaryColor
                onClicked: panel.win.cfg.mapType = "dark"
            }
        }

        Label {
            visible: panel.mode === "map"
            text: qsTr("Barevnost mapy")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }
        Slider {
            visible: panel.mode === "map"
            width: parent.width
            minimumValue: 0.0
            maximumValue: 1.0
            stepSize: 0.05
            value: panel.win.cfg.saturation
            onValueChanged: panel.win.cfg.saturation = value
        }

        TextSwitch {
            visible: panel.mode === "map"
            text: qsTr("Moje poloha")
            checked: panel.win.cfg.showPosition
            onClicked: panel.win.cfg.showPosition = checked
        }
        TextSwitch {
            visible: panel.mode === "map"
            text: qsTr("Vyhladit radar")
            checked: panel.win.cfg.smoothRadar
            onClicked: panel.win.cfg.smoothRadar = checked
        }

        // ---- radar source settings ----
        Label {
            visible: panel.mode === "source"
            text: qsTr("Zdroj dat")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }
        Row {
            visible: panel.mode === "source"
            width: parent.width
            spacing: Theme.paddingSmall
            Repeater {
                model: ["chmi", "dwd", "fmi", "rv"]
                delegate: Button {
                    width: (parent.width - 3 * Theme.paddingSmall) / 4
                    text: R.SOURCES[modelData].label
                    color: panel.win.cfg.radarSource === modelData ? Theme.highlightColor : Theme.primaryColor
                    onClicked: panel.win.setRadarSource(modelData)
                }
            }
        }

        TextSwitch {
            visible: panel.mode === "source" && panel.win.cfg.radarSource === "chmi"
            text: qsTr("Blesky (ČHMÚ)")
            checked: panel.win.cfg.lightning
            onClicked: {
                panel.win.cfg.lightning = checked;
                panel.win.refresh();
            }
        }

        Label {
            visible: panel.mode === "source"
            text: qsTr("Délka historie")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }
        Row {
            visible: panel.mode === "source"
            width: parent.width
            spacing: Theme.paddingSmall
            Repeater {
                model: [60, 120, 360]
                delegate: Button {
                    width: (parent.width - 2 * Theme.paddingSmall) / 3
                    text: (modelData / 60) + " h"
                    color: panel.win.cfg.historyMinutes === modelData ? Theme.highlightColor : Theme.primaryColor
                    onClicked: {
                        panel.win.cfg.historyMinutes = modelData;
                        panel.win.refresh();
                    }
                }
            }
        }

        Label {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: (panel.win.cfg.radarSource === "chmi"
                   ? qsTr("Data radaru: ČHMÚ.")
                   : qsTr("Data radaru: %1. Načítání trvá déle, protože se stahuje jeden obrázek na každých 5 minut historie.").arg(R.SOURCES[panel.win.cfg.radarSource].attribution))
                  + " " + qsTr("Mapa: © Esri, © OpenTopoMap.")
        }
    }
}
