import QtQuick
import QtQuick.Controls
import QtQuick.Window

Window {
    id: testWindow
    title: "定点打击测试"
    width: 800
    height: 600
    visible: false
    color: "#1e1e2e"

    Rectangle {
        anchors.fill: parent
        color: "#2d2d3d"

        Text {
            anchors.centerIn: parent
            text: "定点打击窗口加载成功！"
            color: "#00E5FF"
            font.pixelSize: 24
            font.bold: true
        }

        Button {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: 20
            text: "关闭"
            onClicked: testWindow.close()
        }
    }
}
