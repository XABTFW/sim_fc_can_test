/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Controllers
import QGroundControl.Palette
import QGroundControl.ScreenTools

AnalyzePage {
    id: root
    pageComponent: pageComponent
    pageDescription: qsTr("sim_fc_cantest")
    allowPopout: true

    property real _margins: ScreenTools.defaultFontPixelWidth
    property var fcData: ({
        voltage: "--", current: "--", soc: "--", tmax: "--", tmin: "--", maxv: "--", minv: "--",
        insulation: "--", dcdcVoltage: "--", dcdcCurrent: "--", dcdcTemp: "--",
        warning1: "--", warning2: "--", warning3: "--", workState: "--",
        rx: 0, tx: 0, errors: 0, last: "--"
    })
    property var simData: ({
        packCmd: "--", channelCmd: "--", flightState: "--", packPower: "--",
        ch1: "--", ch2: "--", ch3: "--", ch4: "--", rx: 0, tx: 0, errors: 0, last: "--"
    })
    property bool sendCoolingDown: false
    property string lastCommand: "--"

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    ListModel { id: fcLogModel }
    ListModel { id: simLogModel }

    component SectionTitle: QGCLabel {
        font.pointSize: ScreenTools.mediumFontPointSize
        font.bold: true
        Layout.fillWidth: true
    }

    component ValueCell: ColumnLayout {
        property string label
        property string value
        Layout.fillWidth: true

        QGCLabel {
            text: label
            color: qgcPal.text
            opacity: 0.75
        }

        QGCLabel {
            text: value
            font.bold: true
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }

    component LogTable: ColumnLayout {
        property var logModel
        Layout.fillWidth: true
        Layout.fillHeight: true

        RowLayout {
            Layout.fillWidth: true
            SectionTitle { text: qsTr("原始帧日志") }
            QGCButton {
                text: qsTr("清空")
                onClicked: logModel.clear()
            }
        }

        ListView {
            id: table
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: logModel

            delegate: Rectangle {
                width: table.width
                height: logRow.implicitHeight + _margins
                color: index % 2 ? qgcPal.window : qgcPal.windowShade

                RowLayout {
                    id: logRow
                    anchors.fill: parent
                    anchors.margins: _margins / 2
                    spacing: _margins

                    QGCLabel { text: time; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 9 }
                    QGCLabel { text: direction; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 4; font.bold: true }
                    QGCLabel { text: canId; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 12 }
                    QGCLabel { text: dlc; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 4 }
                    QGCLabel { text: hexData; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 28; elide: Text.ElideRight }
                    QGCLabel { text: name; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16 }
                    QGCLabel { text: parsed; Layout.fillWidth: true; elide: Text.ElideRight }
                }
            }
        }
    }

    SimFCCANTestController {
        id: controller

        onFrameReceived: function(role, direction, canId, len, hexData, rawText) {
            root.addFrame(role, direction, canId, len, hexData, rawText)
        }

        onCommandSent: function(role, canId, hexData) {
            if (canId === "module") {
                lastCommand = qsTr("%1 Vehicle=%2: %3")
                    .arg(role === "sim" ? qsTr("SIM电池端") : qsTr("FC端"))
                    .arg(controller.activeVehicleId)
                    .arg(hexData)
            } else {
                lastCommand = qsTr("%1 Vehicle=%2: hybrid_bms_can send %3 %4")
                    .arg(role === "sim" ? qsTr("SIM电池端") : qsTr("FC端"))
                    .arg(controller.activeVehicleId)
                    .arg(canId)
                    .arg(hexData)
            }
            errorLabel.text = ""
        }

        onErrorText: function(text) {
            errorLabel.text = text
        }
    }

    Timer {
        id: sendCooldownTimer
        interval: 1050
        repeat: false
        onTriggered: sendCoolingDown = false
    }

    function normalizeId(canId) {
        var value = canId.toString().trim().toUpperCase()
        return value.indexOf("0X") === 0 ? "0x" + value.substring(2) : "0x" + value
    }

    function byteArray(hexText) {
        var clean = hexText.replace(/0x/ig, " ").replace(/,/g, " ").replace(/[^0-9A-Fa-f]/g, " ")
        var parts = clean.trim().split(/\s+/)
        var out = []
        for (var i = 0; i < parts.length; i++) {
            if (parts[i].length === 0) {
                continue
            }
            if (parts[i].length > 2) {
                for (var j = 0; j < parts[i].length; j += 2) {
                    out.push(parseInt(parts[i].substring(j, j + 2), 16) & 0xff)
                }
            } else {
                out.push(parseInt(parts[i], 16) & 0xff)
            }
        }
        return out
    }

    function hexBytes(bytes) {
        var out = []
        for (var i = 0; i < bytes.length; i++) {
            out.push(("0" + (bytes[i] & 0xff).toString(16)).slice(-2).toUpperCase())
        }
        return out.join(" ")
    }

    function u16(bytes, index) {
        if (bytes.length <= index + 1) {
            return 0
        }
        return (bytes[index] & 0xff) | ((bytes[index + 1] & 0xff) << 8)
    }

    function setU16(bytes, index, value) {
        bytes[index] = value & 0xff
        bytes[index + 1] = (value >> 8) & 0xff
    }

    function protocolName(canId) {
        switch (normalizeId(canId)) {
        case "0x0401F456": return qsTr("电池组控制命令")
        case "0x0402F456": return qsTr("输出通道控制命令")
        case "0x040156F4": return qsTr("电池组控制命令反馈")
        case "0x040256F4": return qsTr("输出通道控制命令反馈")
        case "0x041256F4": return qsTr("MBMS状态帧")
        case "0x041356F4": return qsTr("MBMS数据帧")
        case "0x042056F4": return qsTr("低压电池运行数据")
        case "0x043056F4": return qsTr("DCDC运行数据")
        default: return qsTr("自定义帧")
        }
    }

    function onOff(v) {
        return v === 0xff ? qsTr("上电") : qsTr("下电")
    }

    function flight(v) {
        return v === 0xff ? qsTr("飞行状态") : qsTr("地面状态")
    }

    function workStateText(v) {
        var states = []
        if (v & 0x01) states.push(qsTr("充电"))
        if (v & 0x02) states.push(qsTr("放电"))
        if (v & 0x04) states.push(qsTr("待机"))
        if (v & 0x10) states.push(qsTr("故障"))
        return states.length ? states.join("/") : "--"
    }

    function parseFrame(canId, hexText, role, direction) {
        var id = normalizeId(canId)
        var bytes = byteArray(hexText)
        var text = protocolName(id)

        if (id === "0x0401F456" && bytes.length >= 2) {
            text += ": " + flight(bytes[0]) + ", 电池组" + onOff(bytes[1])
            if (role === "sim" && direction === "RX") {
                simData.flightState = flight(bytes[0])
                simData.packPower = onOff(bytes[1])
                simData.packCmd = text
            }
        } else if (id === "0x0402F456" && bytes.length >= 4) {
            text += ": 放电01 " + onOff(bytes[0]) + ", 放电02 " + onOff(bytes[1]) + ", 放电03 " + onOff(bytes[2]) + ", 放电04 " + onOff(bytes[3])
            if (role === "sim" && direction === "RX") {
                simData.ch1 = onOff(bytes[0])
                simData.ch2 = onOff(bytes[1])
                simData.ch3 = onOff(bytes[2])
                simData.ch4 = onOff(bytes[3])
                simData.channelCmd = text
            }
        } else if (id === "0x041256F4" && bytes.length >= 11) {
            var warn1 = u16(bytes, 7)
            var warn2 = u16(bytes, 9)
            text += ": 工作状态=" + workStateText(bytes[6]) + ", 一级告警=0x" + warn1.toString(16).toUpperCase() + ", 二级告警=0x" + warn2.toString(16).toUpperCase()
            if (role === "fc" && direction === "RX") {
                fcData.workState = workStateText(bytes[6])
                fcData.warning1 = "0x" + warn1.toString(16).toUpperCase()
                fcData.warning2 = "0x" + warn2.toString(16).toUpperCase()
            }
        } else if (id === "0x041356F4" && bytes.length >= 55) {
            var bp = (u16(bytes, 1) * 0.1).toFixed(1)
            var current = (u16(bytes, 23) * 0.1 - 200).toFixed(1)
            var maxv = u16(bytes, 39)
            var minv = u16(bytes, 43)
            var tmax = bytes[47] - 40
            var tmin = bytes[50] - 40
            var insulation = u16(bytes, 53)
            text += ": B+/B-=" + bp + "V, 总负电流=" + current + "A, 最高温度=" + tmax + "C, 最低温度=" + tmin + "C"
            if (role === "fc" && direction === "RX") {
                fcData.voltage = bp + " V"
                fcData.current = current + " A"
                fcData.tmax = tmax + " C"
                fcData.tmin = tmin + " C"
                fcData.maxv = maxv + " mV"
                fcData.minv = minv + " mV"
                fcData.insulation = insulation + " ohm"
            }
        } else if (id === "0x042056F4" && bytes.length >= 23) {
            var voltage = (u16(bytes, 0) * 0.1).toFixed(1)
            var lowCurrent = (u16(bytes, 2) * 0.1 - 30000).toFixed(1)
            var soc = (u16(bytes, 4) * 0.1).toFixed(1)
            text += ": 总压=" + voltage + "V, 电流=" + lowCurrent + "A, SOC=" + soc + "%"
            if (role === "fc" && direction === "RX") {
                fcData.voltage = voltage + " V"
                fcData.current = lowCurrent + " A"
                fcData.soc = soc + " %"
                fcData.maxv = u16(bytes, 8) + " mV"
                fcData.minv = u16(bytes, 11) + " mV"
                fcData.tmax = (bytes[14] - 40) + " C"
                fcData.tmin = (bytes[16] - 40) + " C"
                fcData.warning1 = "0x" + bytes[20].toString(16).toUpperCase()
                fcData.warning2 = "0x" + bytes[21].toString(16).toUpperCase()
                fcData.warning3 = "0x" + bytes[22].toString(16).toUpperCase()
            }
        } else if (id === "0x043056F4" && bytes.length >= 8) {
            var dcdcV = (u16(bytes, 0) * 0.1).toFixed(1)
            var dcdcI = (u16(bytes, 2) * 0.1 - 500).toFixed(1)
            var dcdcT = bytes[5] - 40
            text += ": 输出电压=" + dcdcV + "V, 输出电流=" + dcdcI + "A, 温度=" + dcdcT + "C"
            if (role === "fc" && direction === "RX") {
                fcData.dcdcVoltage = dcdcV + " V"
                fcData.dcdcCurrent = dcdcI + " A"
                fcData.dcdcTemp = dcdcT + " C"
            }
        }

        fcData = fcData
        simData = simData
        return text
    }

    function addFrame(role, direction, canId, len, hexData, rawText) {
        var now = new Date().toLocaleTimeString()
        var parsed = parseFrame(canId, hexData, role, direction)
        var item = {
            time: now,
            direction: direction,
            canId: normalizeId(canId),
            dlc: len,
            hexData: hexData,
            name: protocolName(canId),
            parsed: parsed
        }

        if (role === "sim") {
            if (direction === "RX") simData.rx++
            if (direction === "TX") simData.tx++
            simData.last = now
            simData = simData
            simLogModel.insert(0, item)
            if (simLogModel.count > 120) simLogModel.remove(120)
        } else {
            if (direction === "RX") fcData.rx++
            if (direction === "TX") fcData.tx++
            fcData.last = now
            fcData = fcData
            fcLogModel.insert(0, item)
            if (fcLogModel.count > 120) fcLogModel.remove(120)
        }
    }

    function sendFrame(canId, hexData) {
        if (sendCoolingDown) {
            errorLabel.text = qsTr("发送过快，请稍后再试")
            return
        }

        sendCoolingDown = true
        sendCooldownTimer.restart()
        controller.sendFrame(canId, hexData)
    }

    function sendFcControl(flightState, packPower, channelMask) {
        if (sendCoolingDown) {
            errorLabel.text = qsTr("发送过快，请稍后再试")
            return
        }

        sendCoolingDown = true
        sendCooldownTimer.restart()
        controller.sendFcControl(flightState, packPower, channelMask)
    }

    function buildMbmsDataFrame(voltage, current, maxV, minV, tMax, tMin, insulation) {
        var bytes = []
        for (var i = 0; i < 55; i++) bytes.push(0)
        bytes[0] = 1
        setU16(bytes, 1, Math.round(Number(voltage) * 10))
        setU16(bytes, 3, Math.round(Number(voltage) * 10))
        setU16(bytes, 23, Math.round((Number(current) + 200) * 10))
        setU16(bytes, 39, Math.round(Number(maxV)))
        setU16(bytes, 43, Math.round(Number(minV)))
        bytes[47] = Math.round(Number(tMax) + 40)
        bytes[50] = Math.round(Number(tMin) + 40)
        setU16(bytes, 53, Math.round(Number(insulation)))
        return hexBytes(bytes)
    }

    Component {
        id: pageComponent

        ColumnLayout {
            width: availableWidth
            height: availableHeight
            spacing: _margins

            RowLayout {
                Layout.fillWidth: true

                QGCLabel {
                    text: controller.activeVehicleAvailable ?
                              qsTr("当前连接 Vehicle sysid: %1").arg(controller.activeVehicleId) :
                              qsTr("未连接 Vehicle")
                    color: controller.activeVehicleAvailable ? qgcPal.text : qgcPal.warningText
                }

                QGCLabel {
                    text: qsTr("本机角色")
                }

                QGCLabel {
                    text: qsTr("CAN设备")
                }

                QGCTextField {
                    id: canDeviceField
                    text: "can0"
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                }

                QGCLabel {
                    text: qsTr("SIM周期ms")
                }

                QGCTextField {
                    id: startPeriodField
                    text: "1000"
                    validator: IntValidator { bottom: 20; top: 5000 }
                    inputMethodHints: Qt.ImhDigitsOnly
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                }

                QGCButton {
                    text: qsTr("启动当前角色")
                    enabled: controller.activeVehicleAvailable && !sendCoolingDown
                    onClicked: {
                        sendCoolingDown = true
                        sendCooldownTimer.restart()
                        controller.startModule(canDeviceField.text, parseInt(startPeriodField.text))
                    }
                }

                QGCButton {
                    text: qsTr("停止")
                    enabled: controller.activeVehicleAvailable && !sendCoolingDown
                    onClicked: {
                        sendCoolingDown = true
                        sendCooldownTimer.restart()
                        controller.stopModule()
                    }
                }

                QGCLabel {
                    id: errorLabel
                    Layout.fillWidth: true
                    color: qgcPal.warningText
                }
            }

            TabBar {
                id: tabs
                Layout.fillWidth: true
                onCurrentIndexChanged: controller.vehicleRole = currentIndex === 0 ? "fc" : "sim"
                TabButton { text: qsTr("FC") }
                TabButton { text: qsTr("SIM") }
            }

            RowLayout {
                Layout.fillWidth: true
                QGCLabel {
                    text: qsTr("最后提交")
                }
                QGCLabel {
                    text: lastCommand
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    opacity: 0.75
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: tabs.currentIndex

                Loader { sourceComponent: fcPage }
                Loader { sourceComponent: simPage }
            }
        }
    }

    Component {
        id: fcPage

        RowLayout {
            spacing: _margins

            ColumnLayout {
                Layout.preferredWidth: parent.width * 0.34
                Layout.fillHeight: true

                SectionTitle { text: qsTr("控制命令") }
                GridLayout {
                    columns: 2
                    Layout.fillWidth: true

                    QGCLabel { text: qsTr("飞行状态") }
                    Switch { id: flightSwitch; text: checked ? qsTr("飞行状态") : qsTr("地面状态") }
                    QGCLabel { text: qsTr("电池组") }
                    Switch { id: packSwitch; text: checked ? qsTr("上电") : qsTr("下电") }
                    QGCLabel { text: qsTr("放电01") }
                    Switch { id: ch1Switch; text: checked ? qsTr("上电") : qsTr("下电") }
                    QGCLabel { text: qsTr("放电02") }
                    Switch { id: ch2Switch; text: checked ? qsTr("上电") : qsTr("下电") }
                    QGCLabel { text: qsTr("放电03") }
                    Switch { id: ch3Switch; text: checked ? qsTr("上电") : qsTr("下电") }
                    QGCLabel { text: qsTr("放电04") }
                    Switch { id: ch4Switch; text: checked ? qsTr("上电") : qsTr("下电") }
                }

                RowLayout {
                    QGCButton {
                        text: qsTr("发送电池组")
                        enabled: controller.activeVehicleAvailable && !sendCoolingDown
                        onClicked: sendFrame("0x0401F456", hexBytes([flightSwitch.checked ? 0xff : 0x00, packSwitch.checked ? 0xff : 0x00]))
                    }
                    QGCButton {
                        text: qsTr("发送通道")
                        enabled: controller.activeVehicleAvailable && !sendCoolingDown
                        onClicked: sendFrame("0x0402F456", hexBytes([ch1Switch.checked ? 0xff : 0x00, ch2Switch.checked ? 0xff : 0x00, ch3Switch.checked ? 0xff : 0x00, ch4Switch.checked ? 0xff : 0x00]))
                    }
                }
                QGCButton {
                    text: qsTr("发送全部控制命令")
                    Layout.fillWidth: true
                    primary: true
                    enabled: controller.activeVehicleAvailable && !sendCoolingDown
                    onClicked: sendFcControl(flightSwitch.checked, packSwitch.checked, (ch1Switch.checked ? 1 : 0) | (ch2Switch.checked ? 2 : 0) | (ch3Switch.checked ? 4 : 0) | (ch4Switch.checked ? 8 : 0))
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true

                SectionTitle { text: qsTr("飞控端收到的电池数据") }
                GridLayout {
                    columns: 4
                    Layout.fillWidth: true
                    rowSpacing: _margins
                    columnSpacing: _margins * 2

                    ValueCell { label: qsTr("总压"); value: fcData.voltage }
                    ValueCell { label: qsTr("总电流"); value: fcData.current }
                    ValueCell { label: qsTr("SOC"); value: fcData.soc }
                    ValueCell { label: qsTr("最高温度"); value: fcData.tmax }
                    ValueCell { label: qsTr("最低温度"); value: fcData.tmin }
                    ValueCell { label: qsTr("MaxV"); value: fcData.maxv }
                    ValueCell { label: qsTr("MinV"); value: fcData.minv }
                    ValueCell { label: qsTr("绝缘值"); value: fcData.insulation }
                    ValueCell { label: qsTr("DCDC输出电压"); value: fcData.dcdcVoltage }
                    ValueCell { label: qsTr("DCDC输出电流"); value: fcData.dcdcCurrent }
                    ValueCell { label: qsTr("DCDC温度"); value: fcData.dcdcTemp }
                    ValueCell { label: qsTr("工作状态"); value: fcData.workState }
                    ValueCell { label: qsTr("一级告警"); value: fcData.warning1 }
                    ValueCell { label: qsTr("二级告警"); value: fcData.warning2 }
                    ValueCell { label: qsTr("三级告警"); value: fcData.warning3 }
                    ValueCell { label: qsTr("最后收到"); value: fcData.last }
                    ValueCell { label: qsTr("CAN RX"); value: fcData.rx.toString() }
                    ValueCell { label: qsTr("CAN TX"); value: fcData.tx.toString() }
                    ValueCell { label: qsTr("errors"); value: fcData.errors.toString() }
                }

                LogTable { logModel: fcLogModel }
            }
        }
    }

    Component {
        id: simPage

        RowLayout {
            spacing: _margins

            ColumnLayout {
                Layout.preferredWidth: parent.width * 0.34
                Layout.fillHeight: true

                SectionTitle { text: qsTr("手动发送协议帧") }
                ComboBox {
                    id: simFrameType
                    Layout.fillWidth: true
                    textRole: "text"
                    valueRole: "canId"
                    model: [
                        { text: qsTr("电池组控制命令反馈 0x040156F4"), canId: "0x040156F4", data: "00 00" },
                        { text: qsTr("输出通道控制命令反馈 0x040256F4"), canId: "0x040256F4", data: "00 00 00 00" },
                        { text: qsTr("MBMS状态帧 0x041256F4"), canId: "0x041256F4", data: "00 00 00 00 00 00 04 00 00 00 00" },
                        { text: qsTr("MBMS数据帧 0x041356F4"), canId: "0x041356F4", data: "01 74 0E 74 0E 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 98 08 00 00 00 00 00 00 00 00 00 00 00 00 00 00 74 0E 00 00 42 0E 00 00 46 00 00 41 00 00 88 13" },
                        { text: qsTr("低压电池运行数据 0x042056F4"), canId: "0x042056F4", data: "74 0E E8 03 20 03 00 00 74 0E 00 42 0E 00 46 00 41 00 00 04 00 00 00" },
                        { text: qsTr("DCDC运行数据 0x043056F4"), canId: "0x043056F4", data: "0C 01 08 14 00 46 00 46" },
                        { text: qsTr("自定义扩展帧"), canId: "0x041356F4", data: "" }
                    ]
                    onActivated: {
                        simCanId.text = currentValue
                        simHex.text = simFrameType.model[currentIndex].data
                    }
                }

                GridLayout {
                    columns: 2
                    Layout.fillWidth: true
                    QGCLabel { text: qsTr("CAN ID") }
                    QGCTextField { id: simCanId; Layout.fillWidth: true; text: "0x043056F4" }
                    QGCLabel { text: qsTr("HEX数据") }
                    TextArea {
                        id: simHex
                        Layout.fillWidth: true
                        Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 5
                        text: "0C 01 08 14 00 46 00 46"
                        wrapMode: TextEdit.Wrap
                        color: qgcPal.text
                        background: Rectangle {
                            color: qgcPal.window
                            border.color: qgcPal.text
                            border.width: 1
                        }
                    }
                }

                QGCButton {
                    text: qsTr("发送")
                    Layout.fillWidth: true
                    primary: true
                    enabled: controller.activeVehicleAvailable && !sendCoolingDown
                    onClicked: sendFrame(simCanId.text, simHex.text)
                }

                SectionTitle { text: qsTr("模拟数据配置") }
                GridLayout {
                    columns: 2
                    Layout.fillWidth: true

                    QGCLabel { text: qsTr("总压 V") }
                    QGCTextField { id: simVoltage; Layout.fillWidth: true; text: "370.0" }
                    QGCLabel { text: qsTr("总电流 A") }
                    QGCTextField { id: simCurrent; Layout.fillWidth: true; text: "20.0" }
                    QGCLabel { text: qsTr("SOC %") }
                    QGCTextField { id: simSoc; Layout.fillWidth: true; text: "80.0" }
                    QGCLabel { text: qsTr("最高温度 C") }
                    QGCTextField { id: simTMax; Layout.fillWidth: true; text: "30" }
                    QGCLabel { text: qsTr("最低温度 C") }
                    QGCTextField { id: simTMin; Layout.fillWidth: true; text: "25" }
                    QGCLabel { text: qsTr("MaxV mV") }
                    QGCTextField { id: simMaxV; Layout.fillWidth: true; text: "3700" }
                    QGCLabel { text: qsTr("MinV mV") }
                    QGCTextField { id: simMinV; Layout.fillWidth: true; text: "3650" }
                    QGCLabel { text: qsTr("绝缘值") }
                    QGCTextField { id: simInsulation; Layout.fillWidth: true; text: "5000" }
                    QGCLabel { text: qsTr("一级告警") }
                    QGCTextField { id: simWarn1; Layout.fillWidth: true; text: "0" }
                    QGCLabel { text: qsTr("二级告警") }
                    QGCTextField { id: simWarn2; Layout.fillWidth: true; text: "0" }
                    QGCLabel { text: qsTr("周期 ms") }
                    QGCTextField { id: simPeriod; Layout.fillWidth: true; text: "200" }
                }
                QGCButton {
                    text: qsTr("按配置生成 MBMS数据帧")
                    Layout.fillWidth: true
                    onClicked: {
                        simCanId.text = "0x041356F4"
                        simHex.text = buildMbmsDataFrame(simVoltage.text, simCurrent.text, simMaxV.text, simMinV.text, simTMax.text, simTMin.text, simInsulation.text)
                        errorLabel.text = qsTr("已生成 55 字节长帧，请确认后手动发送")
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true

                SectionTitle { text: qsTr("电池端收到的飞控控制命令") }
                GridLayout {
                    columns: 4
                    Layout.fillWidth: true
                    ValueCell { label: qsTr("电池组命令"); value: simData.packCmd }
                    ValueCell { label: qsTr("通道命令"); value: simData.channelCmd }
                    ValueCell { label: qsTr("飞行状态"); value: simData.flightState }
                    ValueCell { label: qsTr("电池组"); value: simData.packPower }
                    ValueCell { label: qsTr("放电01"); value: simData.ch1 }
                    ValueCell { label: qsTr("放电02"); value: simData.ch2 }
                    ValueCell { label: qsTr("放电03"); value: simData.ch3 }
                    ValueCell { label: qsTr("放电04"); value: simData.ch4 }
                    ValueCell { label: qsTr("CAN RX"); value: simData.rx.toString() }
                    ValueCell { label: qsTr("CAN TX"); value: simData.tx.toString() }
                    ValueCell { label: qsTr("errors"); value: simData.errors.toString() }
                    ValueCell { label: qsTr("最后收到"); value: simData.last }
                }

                LogTable { logModel: simLogModel }
            }
        }
    }
}
