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
    id:                 visualMavlinkTestPage
    pageComponent:      pageComponent
    pageDescription:    qsTr("Visual MAVLink communication test interface (simulation <-> ground station <-> flight controller).")
    allowPopout:        true

    property real   _margins:       ScreenTools.defaultFontPixelWidth
    property int    _simCount:      0
    property int    _fcCount:       0
    property string _simLog:        ""
    property string _fcLog:         ""

    function _appendLog(logText, message) {
        if (logText.length === 0) {
            return message
        } else {
            return logText + "\n" + message
        }
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    VisualMavlinkTestController {
        id: vmtController

        onSimDataReceived: function(data) {
            var timestamp = new Date().toLocaleTimeString()
            _simLog = visualMavlinkTestPage._appendLog(_simLog, "[" + timestamp + "] " + data)
            _simCount++
        }

        onFcDataReceived: function(data) {
            var timestamp = new Date().toLocaleTimeString()
            _fcLog = visualMavlinkTestPage._appendLog(_fcLog, "[" + timestamp + "] " + data)
            _fcCount++
        }

        onDataSent: function(data) {
            var timestamp = new Date().toLocaleTimeString()
            // Echo outgoing data on whichever window is the source of the test
            console.log("VMT sent:", data)
        }
    }

    Component {
        id: pageComponent

        Item {
            width:  availableWidth
            height: availableHeight

            ColumnLayout {
                anchors.fill:       parent
                anchors.margins:    ScreenTools.defaultFontPixelHeight
                spacing:            ScreenTools.defaultFontPixelHeight

                // ==========================================
                // 顶部：控制面板
                // ==========================================
                Rectangle {
                    Layout.fillWidth:   true
                    Layout.preferredHeight: controlLayout.implicitHeight + _margins * 2
                    color:              qgcPal.windowShade
                    radius:             ScreenTools.defaultFontPixelWidth * 0.5
                    border.color:       qgcPal.groupBorder
                    border.width:       1

                    GridLayout {
                        id:                 controlLayout
                        anchors.fill:       parent
                        anchors.margins:    _margins
                        columns:            4
                        rowSpacing:         ScreenTools.defaultFontPixelHeight * 0.8
                        columnSpacing:      ScreenTools.defaultFontPixelWidth

                        // --- 第一行：选择仿真/飞控 ---
                        QGCLabel {
                            text: qsTr("仿真 sysid:")
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        }

                        QGCTextField {
                            id:                 simIdInput
                            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 8
                            text:               vmtController.simVehicleId >= 0 ? vmtController.simVehicleId.toString() : ""
                            placeholderText:    qsTr("1")
                            validator:          IntValidator { bottom: 0; top: 255 }
                            onEditingFinished:  if (text.length > 0) vmtController.simVehicleId = parseInt(text)
                        }

                        QGCLabel {
                            text: qsTr("飞控 sysid:")
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        }

                        QGCTextField {
                            id:                 fcIdInput
                            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 8
                            text:               vmtController.fcVehicleId >= 0 ? vmtController.fcVehicleId.toString() : ""
                            placeholderText:    qsTr("2")
                            validator:          IntValidator { bottom: 0; top: 255 }
                            onEditingFinished:  if (text.length > 0) vmtController.fcVehicleId = parseInt(text)
                        }

                        // --- 第二行：测试数值与方向按钮 ---
                        QGCLabel {
                            text: qsTr("测试数值:")
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        }

                        QGCTextField {
                            id:                 valueInput
                            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                            text:               "0"
                            validator:          IntValidator { bottom: -1000000; top: 1000000 }
                        }

                        QGCButton {
                            text:               qsTr("正向: 地面站→仿真→飞控")
                            Layout.fillWidth:   true
                            enabled:            valueInput.text.length > 0
                            onClicked:          vmtController.startForward(parseInt(valueInput.text))
                        }

                        QGCButton {
                            text:               qsTr("反向: 地面站→飞控→仿真")
                            Layout.fillWidth:   true
                            enabled:            valueInput.text.length > 0
                            onClicked:          vmtController.startReverse(parseInt(valueInput.text))
                        }
                    }
                }

                // ==========================================
                // 下部：两个数据窗口
                // ==========================================
                RowLayout {
                    Layout.fillWidth:   true
                    Layout.fillHeight:  true
                    spacing:            ScreenTools.defaultFontPixelHeight * 2

                    // ------ 仿真端窗口 ------
                    ColumnLayout {
                        Layout.fillWidth:   true
                        Layout.fillHeight:  true
                        Layout.minimumWidth: parent.width * 0.45
                        spacing:            ScreenTools.defaultFontPixelHeight

                        QGCLabel {
                            text:               qsTr("仿真端接收") + " (共: " + _simCount + " 条)"
                            font.pointSize:     ScreenTools.mediumFontPointSize
                            font.bold:          true
                            Layout.alignment:   Qt.AlignHCenter
                        }

                        Rectangle {
                            Layout.fillWidth:   true
                            Layout.fillHeight:  true
                            color:              "#2c2c2c"
                            border.color:       qgcPal.groupBorder
                            border.width:       1
                            radius:             ScreenTools.defaultFontPixelWidth * 0.5

                            ScrollView {
                                id:                 simScrollView
                                anchors.fill:       parent
                                anchors.margins:    ScreenTools.defaultFontPixelHeight * 0.5
                                clip:               true

                                TextArea {
                                    readOnly:           true
                                    wrapMode:           TextArea.Wrap
                                    font.family:        ScreenTools.fixedFontFamily
                                    font.pointSize:     ScreenTools.defaultFontPointSize
                                    color:              "#00ff00"
                                    background:         null
                                    text:               visualMavlinkTestPage._simLog.length > 0 ? visualMavlinkTestPage._simLog : "等待仿真端数据..."
                                    onTextChanged:      simScrollView.ScrollBar.vertical.position = 1.0 - simScrollView.ScrollBar.vertical.size
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            QGCButton {
                                text:       qsTr("清空仿真日志")
                                onClicked: {
                                    _simLog = ""
                                    _simCount = 0
                                }
                            }
                        }
                    }

                    // ------ 分隔线 ------
                    Rectangle {
                        Layout.fillHeight:  true
                        Layout.preferredWidth: 1
                        color:              qgcPal.groupBorder
                    }

                    // ------ 飞控端窗口 ------
                    ColumnLayout {
                        Layout.fillWidth:   true
                        Layout.fillHeight:  true
                        Layout.minimumWidth: parent.width * 0.45
                        spacing:            ScreenTools.defaultFontPixelHeight

                        QGCLabel {
                            text:               qsTr("飞控端接收") + " (共: " + _fcCount + " 条)"
                            font.pointSize:     ScreenTools.mediumFontPointSize
                            font.bold:          true
                            Layout.alignment:   Qt.AlignHCenter
                        }

                        Rectangle {
                            Layout.fillWidth:   true
                            Layout.fillHeight:  true
                            color:              "#2c2c2c"
                            border.color:       qgcPal.groupBorder
                            border.width:       1
                            radius:             ScreenTools.defaultFontPixelWidth * 0.5

                            ScrollView {
                                id:                 fcScrollView
                                anchors.fill:       parent
                                anchors.margins:    ScreenTools.defaultFontPixelHeight * 0.5
                                clip:               true

                                TextArea {
                                    readOnly:           true
                                    wrapMode:           TextArea.Wrap
                                    font.family:        ScreenTools.fixedFontFamily
                                    font.pointSize:     ScreenTools.defaultFontPointSize
                                    color:              "#00ff00"
                                    background:         null
                                    text:               visualMavlinkTestPage._fcLog.length > 0 ? visualMavlinkTestPage._fcLog : "等待飞控端数据..."
                                    onTextChanged:      fcScrollView.ScrollBar.vertical.position = 1.0 - fcScrollView.ScrollBar.vertical.size
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            QGCButton {
                                text:       qsTr("清空飞控日志")
                                onClicked: {
                                    _fcLog = ""
                                    _fcCount = 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
