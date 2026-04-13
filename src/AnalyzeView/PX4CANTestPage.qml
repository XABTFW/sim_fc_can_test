/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Palette
import QGroundControl.Controls
import QGroundControl.Controllers
import QGroundControl.ScreenTools

AnalyzePage {
    id:                 px4CANTestPage
    pageComponent:      pageComponent
    pageDescription:    qsTr("PX4 CAN communication test interface.")
    allowPopout:        true

    property real   _margins:       ScreenTools.defaultFontPixelWidth
    property int    _sendCount:     0
    property int    _receiveCount:  0
    property bool   _isSending:     false
    property bool   _isReceiving:   false
    property string _sendLog:       ""
    property string _receiveLog:    ""
    property string _currentFrameId: "0x100"
    property string _currentData:   ""
    property bool   _enableFilter:  false
    property string _filterCanId:   "0x100"

    function _appendLog(logText, placeholderText, message) {
        if (logText === placeholderText || logText.length === 0) {
            return message
        } else {
            return logText + "\n" + message
        }
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    Timer {
        id: continuousSendTimer
        interval: 100  // 默认10Hz
        repeat: true
        property int remainingCount: 0

        onTriggered: {
            if (remainingCount > 0) {
                canController.sendCANData(_currentFrameId + ":" + _currentData)
                remainingCount--

                if (remainingCount === 0) {
                    stop()
                    _isSending = false
                }
            } else {
                stop()
                _isSending = false
            }
        }
    }

    PX4CANTestController {
        id: canController

        onCanDataReceived: function(data) {
            // 过滤逻辑：如果启用了过滤，检查 ID 是否匹配
            if (_enableFilter) {
                // 从消息中提取 ID，格式: "RX[n] XXX:DATA"
                var idMatch = data.match(/RX\[\d+\]\s+([0-9A-Fa-f]+):/);
                if (idMatch) {
                    var receivedId = parseInt(idMatch[1], 16);
                    var filterIdValue = parseInt(_filterCanId.replace(/^0x/i, ""), 16);

                    // 如果 ID 不匹配，忽略这条消息
                    if (receivedId !== filterIdValue) {
                        return;
                    }
                }
            }

            var timestamp = new Date().toLocaleTimeString()
            _receiveLog = px4CANTestPage._appendLog(_receiveLog, qsTr("等待接收数据..."), "[" + timestamp + "] " + data)
            _receiveCount++
        }

        onCanDataSent: function(data) {
            console.log("onCanDataSent triggered:", data)
            var timestamp = new Date().toLocaleTimeString()
            _sendLog = px4CANTestPage._appendLog(_sendLog, qsTr("等待发送数据..."), "[" + timestamp + "] " + data)
            _sendCount++
            console.log("_sendLog updated:", _sendLog)
        }

        onReceiveRunningChanged: function(running) {
            _isReceiving = running
        }
    }

    Component {
        id: pageComponent

        Item {
            width:  availableWidth
            height: availableHeight

            RowLayout {
                anchors.fill:       parent
                anchors.margins:    ScreenTools.defaultFontPixelHeight
                spacing:            ScreenTools.defaultFontPixelHeight * 2

                // ==========================================
                // 左侧：发送区域
                // ==========================================
                ColumnLayout {
                    Layout.fillWidth:   true
                    Layout.fillHeight:  true
                    Layout.minimumWidth: parent.width * 0.45
                    spacing:            ScreenTools.defaultFontPixelHeight

                    // 标题
                    QGCLabel {
                        text:               qsTr("发送数据") + " (共发送: " + _sendCount + " 条)"
                        font.pointSize:     ScreenTools.mediumFontPointSize
                        font.bold:          true
                        Layout.alignment:   Qt.AlignHCenter
                    }

                    // --- 发送控制面板 (卡片式设计) ---
                    Rectangle {
                        Layout.fillWidth:   true
                        Layout.preferredHeight: sendControlLayout.implicitHeight + _margins * 2
                        color:              qgcPal.windowShade  // 较浅的背景色作为控制面板底色
                        radius:             ScreenTools.defaultFontPixelWidth * 0.5
                        border.color:       qgcPal.groupBorder
                        border.width:       1

                        GridLayout {
                            id:                 sendControlLayout
                            anchors.fill:       parent
                            anchors.margins:    _margins
                            columns:            4
                            rowSpacing:         ScreenTools.defaultFontPixelHeight * 0.8
                            columnSpacing:      ScreenTools.defaultFontPixelWidth

                            // --- 第一行：单次发送 ---
                            QGCLabel {
                                text: qsTr("帧 ID:")
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            }

                            QGCTextField {
                                id:                 frameIdInput
                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                                placeholderText:    qsTr("0x100")
                                text:               "0x100"
                                validator:          RegularExpressionValidator { regularExpression: /^(0x)?[0-9A-Fa-f]{1,3}$/ }
                            }

                            QGCTextField {
                                id:                 sendDataInput
                                Layout.fillWidth:   true
                                placeholderText:    qsTr("输入要发送的数据 (Hex)")
                            }

                            QGCButton {
                                text:               qsTr("单次发送")
                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 12
                                enabled:            sendDataInput.text.length > 0 && frameIdInput.text.length > 0
                                onClicked: {
                                    canController.sendCANData(frameIdInput.text + ":" + sendDataInput.text)
                                }
                            }

                            // --- 第二行：连续发送 ---
                            QGCLabel {
                                text: qsTr("连续发送:")
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            }

                            RowLayout {
                                spacing: ScreenTools.defaultFontPixelWidth * 0.5

                                QGCTextField {
                                    id:                 sendFrequencyInput
                                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 6
                                    text:               "10"
                                    validator:          IntValidator { bottom: 1; top: 1000 }
                                }

                                QGCLabel { text: qsTr("Hz") }
                            }

                            RowLayout {
                                spacing: ScreenTools.defaultFontPixelWidth * 0.5
                                Layout.fillWidth: true

                                QGCLabel { text: qsTr("次数:") }

                                QGCTextField {
                                    id:                 sendCountInput
                                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                                    text:               "100"
                                    validator:          IntValidator { bottom: 1; top: 100000 }
                                }

                                QGCLabel { text: qsTr("条") }
                            }

                            QGCButton {
                                text:               _isSending ? qsTr("停止发送") : qsTr("连续发送")
                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 12
                                primary:            _isSending  // 发送中时按钮变为强调色
                                enabled:            sendDataInput.text.length > 0 && frameIdInput.text.length > 0
                                onClicked: {
                                    if (_isSending) {
                                        continuousSendTimer.stop()
                                        _isSending = false
                                    } else {
                                        var frequency = parseInt(sendFrequencyInput.text)
                                        var count = parseInt(sendCountInput.text)
                                        if (frequency > 0 && count > 0) {
                                            // 保存当前输入框的值
                                            _currentFrameId = frameIdInput.text
                                            _currentData = sendDataInput.text

                                            continuousSendTimer.interval = 1000 / frequency
                                            continuousSendTimer.remainingCount = count
                                            continuousSendTimer.start()
                                            _isSending = true
                                        }
                                    }
                                }
                            }

                            // --- 第三行：接收控制 ---
                            QGCLabel {
                                text: qsTr("接收设备:")
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            }

                            QGCTextField {
                                id:                 receiveDeviceInput
                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                                placeholderText:    qsTr("can0")
                                text:               "can0"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.defaultFontPixelWidth

                                QGCCheckBox {
                                    id:         filterCheckBox
                                    text:       qsTr("过滤 ID:")
                                    checked:    _enableFilter
                                    onClicked:  _enableFilter = checked
                                }

                                QGCTextField {
                                    id:                 filterIdInput
                                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                                    placeholderText:    qsTr("0x100")
                                    text:               _filterCanId
                                    enabled:            _enableFilter
                                    onTextChanged:      _filterCanId = text
                                }
                            }

                            QGCButton {
                                text:               _isReceiving ? qsTr("停止接收") : qsTr("开始接收")
                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 12
                                primary:            _isReceiving
                                onClicked: {
                                    if (_isReceiving) {
                                        canController.stopReceive()
                                    } else {
                                        canController.startReceive(receiveDeviceInput.text)
                                    }
                                }
                            }
                        }
                    }

                    // --- 发送日志窗口 ---
                    Rectangle {
                        Layout.fillWidth:   true
                        Layout.fillHeight:  true
                        color:              "#2c2c2c"           // 深色背景
                        border.color:       qgcPal.groupBorder
                        border.width:       1
                        radius:             ScreenTools.defaultFontPixelWidth * 0.5

                        ScrollView {
                            id:                 sendScrollView
                            anchors.fill:       parent
                            anchors.margins:    ScreenTools.defaultFontPixelHeight * 0.5
                            clip:               true

                            TextArea {
                                id:                 sendTextArea
                                readOnly:           true
                                wrapMode:           TextArea.Wrap
                                font.family:        ScreenTools.fixedFontFamily
                                font.pointSize:     ScreenTools.defaultFontPointSize
                                color:              "#00ff00"   // 绿色文字，终端风格
                                background:         null
                                text:               px4CANTestPage._sendLog.length > 0 ? px4CANTestPage._sendLog : "等待发送数据..."
                                onTextChanged:      sendScrollView.ScrollBar.vertical.position = 1.0 - sendScrollView.ScrollBar.vertical.size
                            }
                        }
                    }

                    // 底部清空按钮
                    RowLayout {
                        Layout.fillWidth: true

                        Item { Layout.fillWidth: true } // 占位符，把按钮挤到右边

                        QGCButton {
                            text:               qsTr("清空发送日志")
                            onClicked: {
                                _sendLog = ""
                                _sendCount = 0
                            }
                        }
                    }
                }

                // ==========================================
                // 中间：分隔线
                // ==========================================
                Rectangle {
                    Layout.fillHeight:  true
                    Layout.preferredWidth: 1
                    color:              qgcPal.groupBorder
                }

                // ==========================================
                // 右侧：接收区域
                // ==========================================
                ColumnLayout {
                    Layout.fillWidth:   true
                    Layout.fillHeight:  true
                    Layout.minimumWidth: parent.width * 0.45
                    spacing:            ScreenTools.defaultFontPixelHeight

                    // 标题
                    QGCLabel {
                        text:               qsTr("接收数据") + " (共接收: " + _receiveCount + " 条)"
                        font.pointSize:     ScreenTools.mediumFontPointSize
                        font.bold:          true
                        Layout.alignment:   Qt.AlignHCenter
                    }

                    // --- 接收日志窗口 ---
                    Rectangle {
                        Layout.fillWidth:   true
                        Layout.fillHeight:  true
                        color:              "#2c2c2c"           // 深色背景
                        border.color:       qgcPal.groupBorder
                        border.width:       1
                        radius:             ScreenTools.defaultFontPixelWidth * 0.5

                        ScrollView {
                            id:                 receiveScrollView
                            anchors.fill:       parent
                            anchors.margins:    ScreenTools.defaultFontPixelHeight * 0.5
                            clip:               true

                            TextArea {
                                id:                 receiveTextArea
                                readOnly:           true
                                wrapMode:           TextArea.Wrap
                                font.family:        ScreenTools.fixedFontFamily
                                font.pointSize:     ScreenTools.defaultFontPointSize
                                color:              "#00ff00"   // 绿色文字，终端风格
                                background:         null
                                text:               px4CANTestPage._receiveLog.length > 0 ? px4CANTestPage._receiveLog : "等待接收数据..."
                                onTextChanged:      receiveScrollView.ScrollBar.vertical.position = 1.0 - receiveScrollView.ScrollBar.vertical.size
                            }
                        }
                    }

                    // 底部清空按钮
                    RowLayout {
                        Layout.fillWidth: true

                        Item { Layout.fillWidth: true } // 占位符，把按钮挤到右边

                        QGCButton {
                            text:               qsTr("清空接收日志")
                            onClicked: {
                                _receiveLog = ""
                                _receiveCount = 0
                            }
                        }
                    }
                }
            }
        }
    }
}
