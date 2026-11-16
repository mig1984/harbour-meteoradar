import QtQuick 2.2
import Sailfish.Silica 1.0

// Round translucent button with an icon (for map overlays)
Rectangle {
    id: btn
    property string iconSource: ""
    signal clicked()

    width: Theme.itemSizeMedium
    height: width
    radius: width / 2
    color: mouse.pressed ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)

    Image {
        anchors.centerIn: parent
        width: Theme.iconSizeMedium
        height: width
        source: btn.iconSource
        smooth: true
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: btn.clicked()
    }
}
