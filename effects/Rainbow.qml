// Радуга: семь дуг (assets/rainbow.svg) у нижнего края экрана.
// Weather.qml показывает состояние "rainbow" после дождя при низком солнце.
import QtQuick

Item {
    id: root

    property real opacityScale: 0.65  // заметность дуги

    Image {
        id: bow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // дуга «утоплена» за нижний край — видна только её верхняя часть
        anchors.bottomMargin: -parent.height * 0.28
        width: Math.min(parent.width * 0.55, parent.height * 1.15)
        height: width * 0.56
        fillMode: Image.PreserveAspectFit
        source: Qt.resolvedUrl("../assets/rainbow.svg")
        opacity: 0
        Behavior on opacity {
            NumberAnimation { duration: 3000 }   // проявляется и гаснет плавно
        }
    }

    onVisibleChanged: bow.opacity = visible ? root.opacityScale : 0
    Component.onCompleted: if (visible) bow.opacity = root.opacityScale
}
