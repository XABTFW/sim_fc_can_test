import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

/**
 * 集群操作确认弹窗组件
 * 用于显示组号切换、主机切换、参数变更等操作的确认信息
 * opType: 1=组号变更, 2=角色变更(主机), 3=参数变更, 4=从机状态变更
 */
Rectangle {
    id: swarmOpPopup

    // 属性
    property int sysId: 0
    property int opType: 0          // 1=组号变更, 2=角色变更(主机), 3=参数变更, 4=从机状态变更
    property int result: 0          // 0=成功, 1=失败
    property int oldValue: 0
    property int newValue: 0
    property string message: ""
    property bool isSuccess: result === 0

    // 弹窗队列
    property var messageQueue: []
    property bool isShowing: false

    // 尺寸和位置
    width: 320
    height: 80
    radius: 8

    // 根据opType和result确定颜色
    // opType=3(参数变更)使用蓝色, opType=4(从机)使用青色, 其他根据成功/失败
    color: opType === 3 ? "#2d4a5a" : (opType === 4 ? "#2d5a5a" : (isSuccess ? "#2d5a2d" : "#5a2d2d"))
    border.color: opType === 3 ? "#5e81ac" : (opType === 4 ? "#88c0d0" : (isSuccess ? "#4CAF50" : "#f44336"))
    border.width: 2

    // 默认隐藏
    visible: false
    opacity: 0

    // 定位在右上角
    anchors.right: parent ? parent.right : undefined
    anchors.top: parent ? parent.top : undefined
    anchors.rightMargin: 20
    anchors.topMargin: 100

    // 内容布局
    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // 图标
        Rectangle {
            width: 40
            height: 40
            radius: 20
            color: opType === 3 ? "#5e81ac" : (opType === 4 ? "#88c0d0" : (isSuccess ? "#4CAF50" : "#f44336"))

            Text {
                anchors.centerIn: parent
                text: opType === 3 ? "⚙" : (opType === 4 ? "✈" : (isSuccess ? "✓" : "✗"))
                font.pixelSize: 24
                font.bold: true
                color: "#FFFFFF"
            }
        }

        // 消息文本
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: opType === 3 ? "参数变更" : (opType === 4 ? "从机状态" : (isSuccess ? "操作成功" : "操作失败"))
                font.pixelSize: 14
                font.bold: true
                color: "#00FF88"  // 统一使用电光绿
            }

            Text {
                text: message
                font.pixelSize: 12
                color: "#00FF88"  // 统一使用电光绿
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        // 关闭按钮
        Rectangle {
            width: 24
            height: 24
            radius: 12
            color: mouseArea.containsMouse ? "#ffffff30" : "transparent"

            Text {
                anchors.centerIn: parent
                text: "×"
                font.pixelSize: 18
                color: "#E0E0E0"
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: hidePopup()
            }
        }
    }

    // 6秒自动关闭定时器（时间增加一倍）
    Timer {
        id: autoCloseTimer
        interval: 6000
        onTriggered: hidePopup()
    }

    // 队列处理定时器
    Timer {
        id: queueTimer
        interval: 500
        onTriggered: processQueue()
    }

    // 显示动画
    Behavior on opacity {
        NumberAnimation { duration: 200 }
    }

    Behavior on y {
        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
    }

    // 显示弹窗
    function showPopup(sysId, opType, result, oldValue, newValue, msg) {
        // 过滤空消息
        if (!msg || msg.toString().trim() === "") {
            console.log("[SwarmOperationPopup] 忽略空消息");
            return;
        }

        // 添加到队列
        messageQueue.push({
            sysId: sysId,
            opType: opType,
            result: result,
            oldValue: oldValue,
            newValue: newValue,
            message: msg
        });

        // 如果当前没有显示，立即处理队列
        if (!isShowing) {
            processQueue();
        }
    }

    // 处理队列
    function processQueue() {
        if (messageQueue.length === 0) {
            return;
        }

        var data = messageQueue.shift();
        swarmOpPopup.sysId = data.sysId;
        swarmOpPopup.opType = data.opType;
        swarmOpPopup.result = data.result;
        swarmOpPopup.oldValue = data.oldValue;
        swarmOpPopup.newValue = data.newValue;
        swarmOpPopup.message = data.message;

        // 显示弹窗
        isShowing = true;
        visible = true;
        opacity = 1;

        // 启动自动关闭定时器
        autoCloseTimer.restart();
    }

    // 隐藏弹窗
    function hidePopup() {
        autoCloseTimer.stop();
        opacity = 0;

        // 延迟隐藏，等待动画完成
        hideTimer.start();
    }

    Timer {
        id: hideTimer
        interval: 200
        onTriggered: {
            visible = false;
            isShowing = false;

            // 检查队列中是否还有消息
            if (messageQueue.length > 0) {
                queueTimer.start();
            }
        }
    }
}
