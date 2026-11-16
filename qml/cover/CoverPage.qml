import QtQuick 2.2
import Sailfish.Silica 1.0
import "../js/radar.js" as R
import "../components"

CoverBackground {
    id: cover
    property var win: R.app

    Rectangle {
        anchors.fill: parent
        color: "#0a1620"
    }

    // Same base map and radar overlay as the main page, fitted to the radar
    // rectangle (the cover is not interactive, so no gesture handling matters).
    SlippyMap {
        id: coverMap
        anchors.fill: parent
        mapType: cover.win.cfg.mapType
        saturation: cover.win.cfg.saturation
        centerLon: cover.win.cfg.centerLon
        centerLat: cover.win.cfg.centerLat
        zoom: cover.win.cfg.zoom
        bbox: cover.win.bbox
        bboxKey: cover.win.cfg.radarSource
        radarSource: cover.win.currentRadar
        smoothRadar: true
        visible: cover.win.bbox !== null
    }

    Rectangle {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.paddingLarge
        width: coverTime.width + 2 * Theme.paddingSmall
        height: coverTime.height
        radius: Theme.paddingSmall
        color: cover.win.frameIsForecast ? "#c76a1a" : "#0a7c8a"

        Label {
            id: coverTime
            anchors.centerIn: parent
            text: cover.win.frameLabel
            color: "white"
            font.pixelSize: Theme.fontSizeLarge
        }
    }


    Label {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Theme.paddingLarge
        text: cover.win.loading ? qsTr("Načítám…") : qsTr("Meteoradar")
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
    }

    CoverActionList {
        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: cover.win.refresh()
        }
    }
}
