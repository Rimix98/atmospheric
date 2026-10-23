// Rainbow: seven arcs (assets/rainbow.svg) at the bottom of the screen.
// Weather.qml shows the "rainbow" state after rain while the sun is low.
import QtQuick

Item {
    id: root

    property real opacityScale: 0.65  // arc visibility

    Image {
        id: bow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // the arc is sunk below the bottom edge — only its top part is visible
        anchors.bottomMargin: -parent.height * 0.28
        width: Math.min(parent.width * 0.55, parent.height * 1.15)
        height: width * 0.56
        fillMode: Image.PreserveAspectFit
        source: Qt.resolvedUrl("../assets/rainbow.svg")
        opacity: 0
        Behavior on opacity {
            NumberAnimation { duration: 3000 }   // fades in and out smoothly
        }
    }

    onVisibleChanged: bow.opacity = visible ? root.opacityScale : 0
    Component.onCompleted: if (visible) bow.opacity = root.opacityScale
}
