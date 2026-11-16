import QtQuick 2.2
import Sailfish.Silica 1.0
import QtPositioning 5.2
import QtGraphicalEffects 1.0
import "../components"
import "../js/radar.js" as R

Page {
    id: page

    property var win: R.app
    allowedOrientations: Orientation.All

    property bool panelOpen: false
    // which sheet the settings panel shows: "map" or "source"
    property string panelMode: "map"

    // set explicitly (not as a binding) so that a swipe-close, which assigns
    // panel.open itself, does not break the link to the menu button
    onPanelOpenChanged: panel.open = panelOpen

    // Own position (only when enabled in settings)
    PositionSource {
        id: source
        active: page.win.cfg.showPosition
        updateInterval: 15000
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                page.win.posValid = true;
                page.win.posLat = position.coordinate.latitude;
                page.win.posLon = position.coordinate.longitude;
            }
        }
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: height
        // inside the radar rectangle the map pans itself; outside it the
        // flickable takes the drag, so the pulley menu below works
        interactive: !map.pressInside

        PullDownMenu {
            MenuItem {
                text: qsTr("Nastavení mapy")
                onClicked: { page.panelMode = "map"; page.panelOpen = true; }
            }
            MenuItem {
                text: qsTr("Zdroj radaru")
                onClicked: { page.panelMode = "source"; page.panelOpen = true; }
            }
            MenuItem {
                text: qsTr("Obnovit")
                onClicked: page.win.refresh()
            }
        }

        PushUpMenu {
            MenuItem {
                text: qsTr("Nastavení mapy")
                onClicked: { page.panelMode = "map"; page.panelOpen = true; }
            }
            MenuItem {
                text: qsTr("Zdroj radaru")
                onClicked: { page.panelMode = "source"; page.panelOpen = true; }
            }
            MenuItem {
                text: qsTr("Obnovit")
                onClicked: page.win.refresh()
            }
        }

    SlippyMap {
        id: map
        width: flick.width
        height: flick.height

        centerLon: page.win.cfg.centerLon
        centerLat: page.win.cfg.centerLat
        zoom: page.win.cfg.zoom
        mapType: page.win.cfg.mapType
        saturation: page.win.cfg.saturation

        bbox: page.win.bbox
        bboxKey: page.win.cfg.radarSource
        tileMode: page.win.cfg.radarSource === "rv"
        tileHost: page.win.rvHost
        tilePath: page.win.currentTilePath
        radarSource: page.win.currentRadar
        lightSource: page.win.cfg.lightning ? page.win.currentLight : ""
        radarOpacity: 1.0
        smoothRadar: page.win.cfg.smoothRadar

        posValid: page.win.posValid && page.win.cfg.showPosition
        posLat: page.win.posLat
        posLon: page.win.posLon

        onInteracted: {
            page.win.cfg.centerLon = map.centerLon;
            page.win.cfg.centerLat = map.centerLat;
            page.win.cfg.zoom = map.zoom;
        }
        // tapping the map closes the settings panel
        onTapped: page.panelOpen = false;
    }
    }

    // Time badge (top right), like the Meteor clock label
    Rectangle {
        id: timeBadge
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.paddingLarge + Theme.paddingSmall
        anchors.rightMargin: Theme.paddingLarge
        width: timeText.width + 2 * Theme.paddingMedium
        height: timeText.height + Theme.paddingSmall
        radius: Theme.paddingSmall
        color: page.win.frameIsForecast ? "#c76a1a" : "#0a7c8a"
        opacity: 0.92

        Label {
            id: timeText
            anchors.centerIn: parent
            text: page.win.frameLabel
            color: "white"
            font.pixelSize: Theme.fontSizeLarge
        }
    }

    // Error hint only (dark red box). Loading is shown by the big spinner below.
    Rectangle {
        id: statusBox
        z: 100
        anchors.top: parent.top
        anchors.topMargin: Theme.itemSizeLarge
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: statusText.paintedHeight + 2 * Theme.paddingLarge
        radius: Theme.paddingSmall
        color: "#cc0000"
        visible: page.win.errorText !== ""
        Label {
            id: statusText
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.paddingLarge
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            text: page.win.errorText
        }
    }

    // Big spinner in the middle of the display while the radar is loading
    BusyIndicator {
        id: loadingSpinner
        z: 120
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: (page.win.loading && page.win.frames.length === 0) || map.tilesBusy
        visible: running
        // dark shadow so the spinner stays visible on light map areas
        layer.enabled: true
        layer.effect: DropShadow {
            color: "black"
            radius: 8
            samples: 17
            spread: 0.3
            horizontalOffset: 0
            verticalOffset: 0
        }
    }

    // DWD download progress, shown while frames are still arriving
    Label {
        anchors.top: loadingSpinner.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.paddingMedium
        z: 120
        visible: page.win.loading && page.win.loadTotal > 0
        color: "white"
        font.pixelSize: Theme.fontSizeSmall
        style: Text.Outline
        styleColor: "black"
        text: qsTr("Načítám snímky: %1 / %2").arg(page.win.loadDone).arg(page.win.loadTotal)
    }

    // Right-side round buttons
    Column {
        anchors.right: parent.right
        anchors.rightMargin: Theme.paddingLarge
        anchors.bottom: timeline.top
        anchors.bottomMargin: Theme.paddingLarge
        spacing: Theme.paddingMedium

        MapButton {
            iconSource: "image://theme/icon-m-location"
            onClicked: {
                if (page.win.posValid) {
                    map.centerOn(page.win.posLat, page.win.posLon);
                } else {
                    source.active = true;
                }
            }
        }
    }




    // Bottom timeline with play button
    Rectangle {
        id: timeline
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: attribution.top
        height: Theme.itemSizeLarge
        color: Qt.rgba(0, 0, 0, 0.45)

        RadarTimeline {
            anchors.fill: parent
            anchors.leftMargin: Theme.paddingSmall
            frames: page.win.frames
            current: page.win.current
            playing: page.win.playing
            onSelected: {
                page.win.playing = false;
                page.win.current = index;
            }
            onPlayToggled: {
                // RainViewer: no animation (tile request limit), frames are picked manually
                if (page.win.cfg.radarSource === "rv") return;
                if (!page.win.playing && page.win.frames.length > 0 && page.win.current >= page.win.frames.length - 1)
                    page.win.current = 0;
                page.win.playing = !page.win.playing;
            }
        }
    }

    Label {
        id: attribution
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.paddingSmall
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeExtraSmall * 0.8
        color: "#c0ffffff"
        text: R.SOURCES[page.win.cfg.radarSource].attribution + " · © OpenStreetMap"
    }

    SettingsPanel {
        id: panel
        win: page.win
        mode: page.panelMode
        visible: page.panelOpen
        onOpenChanged: page.panelOpen = open
    }
}
