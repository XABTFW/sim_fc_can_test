import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: strikeWindow
    title: "定点打击控制系统"
    width: 1400
    height: 900
    minimumWidth: 1000
    minimumHeight: 700
    visible: false
    color: "#1e1e2e"

    // FUI 科幻风格配色
    property color primaryColor: "#00E5FF"
    property color secondaryColor: "#00FF88"
    property color accentColor: "#00D4FF"
    property color dangerColor: "#FF3366"
    property color warningColor: "#FFB800"
    property color textColor: "#FFFFFF"
    property color textColorDim: "#6B7280"
    property color panelColor: "#1e1e2e"
    property color sceneColor: "#2d2d3d"
    property color controlColor: "#252A3A"
    property color borderColor: "#00E5FF"

    // 全局状态
    QtObject {
        id: missionState

        // 目标坐标
        property real targetX: 50.0
        property real targetY: 30.0
        property real targetZ: -10.0

        // 飞机状态
        property real droneX: 0.0
        property real droneY: 0.0
        property real droneZ: 0.0

        // 约束模式 0=无约束, 1=垂直, 2=水平
        property int constraintMode: 1
        property real impactAngleV: -90.0
        property real impactAngleH: 0.0

        // 性能参数
        property real maxVelocity: 28.0
        property real maxAcceleration: 15.0
        property real missDistance: 2.0

        // 俯冲拉升
        property bool pullupEnabled: false
        property real pullupDistance: 5.0
        property real pullupAltitude: -30.0
        property real pullupAccel: 10.0

        // 任务状态
        property string status: "IDLE"
        property real distanceToTarget: 0.0
        property real losAngle: 0.0
        property real leadAngle: 0.0
    }

    Rectangle {
        anchors.fill: parent
        color: panelColor

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // 左侧：可视化场景 (70%)
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.7
                color: sceneColor

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // 上方：3D视图 (80%)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: parent.height * 0.8
                        color: sceneColor
                        border.color: Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.2)
                        border.width: 1

                        // 3D视图控制参数
                        property real rotationX: 30
                        property real rotationY: 45
                        property real zoom: 1.0
                        property point lastMousePos: Qt.point(0, 0)
                        property bool needsRepaint: false

                        Canvas {
                            id: canvas3D
                            anchors.fill: parent

                            // 3D投影函数
                            function project3D(x, y, z) {
                                var angleX = parent.rotationX * Math.PI / 180
                                var angleY = parent.rotationY * Math.PI / 180

                                // 绕Y轴旋转
                                var x1 = x * Math.cos(angleY) - z * Math.sin(angleY)
                                var z1 = x * Math.sin(angleY) + z * Math.cos(angleY)

                                // 绕X轴旋转
                                var y2 = y * Math.cos(angleX) - z1 * Math.sin(angleX)
                                var z2 = y * Math.sin(angleX) + z1 * Math.cos(angleX)

                                // 透视投影 - 增强透视效果，整体下移
                                var perspective = 400
                                var scale = perspective / (perspective + z2) * parent.zoom * 2

                                return {
                                    x: width/2 + x1 * scale,
                                    y: height * 0.85 - y2 * scale,  // 从 0.8 改为 0.85，再往下
                                    scale: scale,
                                    depth: z2
                                }
                            }

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)

                                // 绘制稀疏的地面网格 - 只显示主要网格线
                                var gridSize = 15  // 从20改为15，更密集
                                var gridRange = 200  // 从150改为200，更大范围

                                ctx.strokeStyle = Qt.rgba(0.2, 0.5, 0.7, 0.3)  // 稍微明显一点
                                ctx.lineWidth = 1

                                // 只绘制5条X方向和5条Z方向的线
                                for (var i = -gridRange; i <= gridRange; i += gridSize) {
                                    var p1 = project3D(i, 0, -gridRange)
                                    var p2 = project3D(i, 0, gridRange)
                                    ctx.beginPath()
                                    ctx.moveTo(p1.x, p1.y)
                                    ctx.lineTo(p2.x, p2.y)
                                    ctx.stroke()

                                    var p3 = project3D(-gridRange, 0, i)
                                    var p4 = project3D(gridRange, 0, i)
                                    ctx.beginPath()
                                    ctx.moveTo(p3.x, p3.y)
                                    ctx.lineTo(p4.x, p4.y)
                                    ctx.stroke()
                                }

                                // 绘制坐标轴 - 放在左下角，加长
                                var axisOriginX = -60  // 左下角位置
                                var axisOriginY = 0
                                var axisOriginZ = -40
                                var axisLength = 160  // 从80改为160，加高两倍

                                // X轴（红色）
                                ctx.strokeStyle = "#FF3333"
                                ctx.lineWidth = 4
                                var xAxis1 = project3D(axisOriginX, axisOriginY, axisOriginZ)
                                var xAxis2 = project3D(axisOriginX + axisLength, axisOriginY, axisOriginZ)
                                ctx.beginPath()
                                ctx.moveTo(xAxis1.x, xAxis1.y)
                                ctx.lineTo(xAxis2.x, xAxis2.y)
                                ctx.stroke()
                                ctx.fillStyle = "#FF3333"
                                ctx.font = "bold 16px monospace"
                                ctx.fillText("X", xAxis2.x + 10, xAxis2.y)

                                // Y轴（绿色，向上）
                                ctx.strokeStyle = "#33FF33"
                                ctx.lineWidth = 4
                                var yAxis1 = project3D(axisOriginX, axisOriginY, axisOriginZ)
                                var yAxis2 = project3D(axisOriginX, axisOriginY + axisLength, axisOriginZ)
                                ctx.beginPath()
                                ctx.moveTo(yAxis1.x, yAxis1.y)
                                ctx.lineTo(yAxis2.x, yAxis2.y)
                                ctx.stroke()
                                ctx.fillStyle = "#33FF33"
                                ctx.fillText("Y", yAxis2.x + 10, yAxis2.y)

                                // Z轴（蓝色）
                                ctx.strokeStyle = "#3333FF"
                                ctx.lineWidth = 4
                                var zAxis1 = project3D(axisOriginX, axisOriginY, axisOriginZ)
                                var zAxis2 = project3D(axisOriginX, axisOriginY, axisOriginZ + axisLength)
                                ctx.beginPath()
                                ctx.moveTo(zAxis1.x, zAxis1.y)
                                ctx.lineTo(zAxis2.x, zAxis2.y)
                                ctx.stroke()
                                ctx.fillStyle = "#3333FF"
                                ctx.fillText("Z", zAxis2.x + 10, zAxis2.y)

                                // 绘制圆锥形无人机 - 放在视图中心偏上
                                var droneX = missionState.droneX + 10  // 稍微偏移，不在原点
                                var droneY = 0
                                var droneZ = missionState.droneZ + 10
                                var coneHeight = 6   // 从12改为6，再小一倍
                                var coneRadius = 2.5 // 从5改为2.5，再小一倍

                                var faces = []
                                var apex = project3D(droneX, droneY + coneHeight, droneZ)

                                // 减少到6个三角形
                                for (var angle = 0; angle < 360; angle += 60) {
                                    var rad1 = angle * Math.PI / 180
                                    var rad2 = (angle + 60) * Math.PI / 180
                                    var x1 = droneX + coneRadius * Math.cos(rad1)
                                    var z1 = droneZ + coneRadius * Math.sin(rad1)
                                    var x2 = droneX + coneRadius * Math.cos(rad2)
                                    var z2 = droneZ + coneRadius * Math.sin(rad2)

                                    var p1 = project3D(x1, droneY, z1)
                                    var p2 = project3D(x2, droneY, z2)
                                    var avgDepth = (apex.depth + p1.depth + p2.depth) / 3
                                    var brightness = 0.5 + Math.cos(rad1) * 0.3

                                    faces.push({
                                        points: [apex, p1, p2],
                                        depth: avgDepth,
                                        brightness: brightness
                                    })
                                }

                                // 底面
                                var baseCenter = project3D(droneX, droneY, droneZ)
                                faces.push({
                                    points: null,
                                    depth: baseCenter.depth,
                                    brightness: 0.3,
                                    isBase: true,
                                    center: baseCenter,
                                    radius: coneRadius * baseCenter.scale
                                })

                                faces.sort(function(a, b) { return a.depth - b.depth })

                                // 绘制所有面
                                for (var f = 0; f < faces.length; f++) {
                                    var face = faces[f]
                                    if (face.isBase) {
                                        ctx.fillStyle = Qt.rgba(primaryColor.r * face.brightness,
                                                               primaryColor.g * face.brightness,
                                                               primaryColor.b * face.brightness, 0.6)
                                        ctx.strokeStyle = primaryColor
                                        ctx.lineWidth = 2
                                        ctx.beginPath()
                                        ctx.arc(face.center.x, face.center.y, face.radius, 0, 2 * Math.PI)
                                        ctx.fill()
                                        ctx.stroke()
                                    } else {
                                        var pts = face.points
                                        ctx.fillStyle = Qt.rgba(primaryColor.r * face.brightness,
                                                               primaryColor.g * face.brightness,
                                                               primaryColor.b * face.brightness, 0.8)
                                        ctx.strokeStyle = Qt.rgba(primaryColor.r, primaryColor.g, primaryColor.b, 0.9)
                                        ctx.lineWidth = 1.5
                                        ctx.beginPath()
                                        ctx.moveTo(pts[0].x, pts[0].y)
                                        ctx.lineTo(pts[1].x, pts[1].y)
                                        ctx.lineTo(pts[2].x, pts[2].y)
                                        ctx.closePath()
                                        ctx.fill()
                                        ctx.stroke()
                                    }
                                }

                                // 顶点高亮 - 去掉阴影效果
                                ctx.fillStyle = "#FFFFFF"
                                ctx.beginPath()
                                ctx.arc(apex.x, apex.y, 4, 0, 2 * Math.PI)
                                ctx.fill()

                                // 信息显示
                                ctx.fillStyle = textColor
                                ctx.font = "12px monospace"
                                ctx.fillText("高度: " + coneHeight.toFixed(1) + "m", 10, 30)
                                ctx.fillText("位置: (" + droneX.toFixed(1) + ", " + droneZ.toFixed(1) + ")", 10, 50)
                            }

                            // 只在需要时刷新，不是一直刷新
                            Timer {
                                id: refreshTimer
                                interval: 200  // 从50ms改为200ms
                                running: false  // 默认不运行
                                repeat: false
                                onTriggered: {
                                    canvas3D.requestPaint()
                                    parent.needsRepaint = false
                                }
                            }

                            // 监听状态变化
                            Connections {
                                target: missionState
                                function onDroneXChanged() { if (!refreshTimer.running) refreshTimer.start() }
                                function onDroneYChanged() { if (!refreshTimer.running) refreshTimer.start() }
                                function onDroneZChanged() { if (!refreshTimer.running) refreshTimer.start() }
                            }
                        }

                        // MouseArea 作为 Canvas 的兄弟元素
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            onPressed: (mouse) => {
                                parent.lastMousePos = Qt.point(mouse.x, mouse.y)
                            }

                            onPositionChanged: (mouse) => {
                                if (mouse.buttons & Qt.LeftButton) {
                                    var dx = mouse.x - parent.lastMousePos.x
                                    var dy = mouse.y - parent.lastMousePos.y
                                    parent.rotationY += dx * 0.5
                                    parent.rotationX += dy * 0.5
                                    parent.lastMousePos = Qt.point(mouse.x, mouse.y)
                                    canvas3D.requestPaint()  // 立即重绘
                                }
                            }

                            onWheel: (wheel) => {
                                var delta = wheel.angleDelta.y / 120
                                parent.zoom *= (1 + delta * 0.1)
                                parent.zoom = Math.max(0.3, Math.min(3, parent.zoom))
                                canvas3D.requestPaint()  // 立即重绘
                            }

                            onDoubleClicked: {
                                parent.rotationX = 30
                                parent.rotationY = 45
                                parent.zoom = 1.0
                                canvas3D.requestPaint()  // 立即重绘
                            }
                        }

                        Text {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 10
                            text: "3D 视图 (拖动旋转 | 滚轮缩放 | 双击重置)"
                            font.pixelSize: 11
                            font.bold: true
                            color: primaryColor
                            z: 10
                        }

                        // 视角信息
                        Text {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 10
                            text: "旋转: " + parent.rotationX.toFixed(0) + "° / " + parent.rotationY.toFixed(0) + "°\n缩放: " + parent.zoom.toFixed(1) + "x"
                            font.pixelSize: 9
                            color: textColorDim
                            horizontalAlignment: Text.AlignRight
                            z: 10
                        }
                    }

                    // 下方：2D俯视图 (20%)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: sceneColor

                        // 视图控制参数
                        property real viewOffsetX: 0
                        property real viewOffsetY: 0
                        property real viewScale: 3
                        property point dragStart: Qt.point(0, 0)

                Canvas {
                    id: canvas
                    anchors.fill: parent

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        // 绘制网格
                        ctx.strokeStyle = Qt.rgba(0.3, 0.3, 0.3, 0.5)
                        ctx.lineWidth = 1
                        var gridSize = 40
                        for (var x = 0; x < width; x += gridSize) {
                            ctx.beginPath()
                            ctx.moveTo(x, 0)
                            ctx.lineTo(x, height)
                            ctx.stroke()
                        }
                        for (var y = 0; y < height; y += gridSize) {
                            ctx.beginPath()
                            ctx.moveTo(0, y)
                            ctx.lineTo(width, y)
                            ctx.stroke()
                        }

                        // 坐标系原点（考虑偏移）
                        var centerX = width / 2 + parent.viewOffsetX
                        var centerY = height / 2 + parent.viewOffsetY
                        var scale = parent.viewScale

                        // 绘制坐标轴
                        // X轴（北，红色）
                        ctx.strokeStyle = "#FF0000"
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        ctx.moveTo(centerX, centerY)
                        ctx.lineTo(centerX, centerY - 100)
                        ctx.stroke()
                        ctx.fillStyle = "#FF0000"
                        ctx.font = "14px monospace"
                        ctx.fillText("N", centerX + 5, centerY - 105)

                        // Y轴（东，绿色）
                        ctx.strokeStyle = "#00FF00"
                        ctx.beginPath()
                        ctx.moveTo(centerX, centerY)
                        ctx.lineTo(centerX + 100, centerY)
                        ctx.stroke()
                        ctx.fillStyle = "#00FF00"
                        ctx.fillText("E", centerX + 105, centerY + 5)

                        // 绘制飞机（青色三角形）
                        var droneScreenX = centerX + missionState.droneY * scale
                        var droneScreenY = centerY - missionState.droneX * scale
                        ctx.fillStyle = primaryColor
                        ctx.beginPath()
                        ctx.moveTo(droneScreenX, droneScreenY - 10)
                        ctx.lineTo(droneScreenX - 8, droneScreenY + 10)
                        ctx.lineTo(droneScreenX + 8, droneScreenY + 10)
                        ctx.closePath()
                        ctx.fill()

                        // 绘制目标（红色圆圈）
                        var targetScreenX = centerX + missionState.targetY * scale
                        var targetScreenY = centerY - missionState.targetX * scale
                        ctx.strokeStyle = dangerColor
                        ctx.fillStyle = Qt.rgba(dangerColor.r, dangerColor.g, dangerColor.b, 0.3)
                        ctx.lineWidth = 3
                        ctx.beginPath()
                        ctx.arc(targetScreenX, targetScreenY, 15, 0, 2 * Math.PI)
                        ctx.fill()
                        ctx.stroke()

                        // 绘制轨迹线
                        ctx.strokeStyle = accentColor
                        ctx.lineWidth = 2
                        ctx.setLineDash([5, 5])
                        ctx.beginPath()
                        ctx.moveTo(droneScreenX, droneScreenY)
                        ctx.lineTo(targetScreenX, targetScreenY)
                        ctx.stroke()
                        ctx.setLineDash([])

                        // 绘制距离标签
                        ctx.fillStyle = textColor
                        ctx.font = "12px monospace"
                        var midX = (droneScreenX + targetScreenX) / 2
                        var midY = (droneScreenY + targetScreenY) / 2
                        ctx.fillText(missionState.distanceToTarget.toFixed(1) + "m", midX + 10, midY)
                    }

                    // 鼠标拖动
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onPressed: (mouse) => {
                            if (mouse.button === Qt.LeftButton) {
                                parent.parent.dragStart = Qt.point(mouse.x, mouse.y)
                            }
                        }

                        onPositionChanged: (mouse) => {
                            if (mouse.buttons & Qt.LeftButton) {
                                var dx = mouse.x - parent.parent.dragStart.x
                                var dy = mouse.y - parent.parent.dragStart.y
                                parent.parent.viewOffsetX += dx
                                parent.parent.viewOffsetY += dy
                                parent.parent.dragStart = Qt.point(mouse.x, mouse.y)
                                canvas.requestPaint()
                            }
                        }

                        onWheel: (wheel) => {
                            var delta = wheel.angleDelta.y / 120
                            parent.parent.viewScale *= (1 + delta * 0.1)
                            parent.parent.viewScale = Math.max(0.5, Math.min(10, parent.parent.viewScale))
                            canvas.requestPaint()
                        }

                        onDoubleClicked: {
                            parent.parent.viewOffsetX = 0
                            parent.parent.viewOffsetY = 0
                            parent.parent.viewScale = 3
                            canvas.requestPaint()
                        }
                    }

                    // 只在数据变化时刷新
                    Timer {
                        id: canvas2DTimer
                        interval: 200  // 从50ms改为200ms
                        running: false
                        repeat: false
                        onTriggered: canvas.requestPaint()
                    }

                    // 监听状态变化
                    Connections {
                        target: missionState
                        function onDroneXChanged() { if (!canvas2DTimer.running) canvas2DTimer.start() }
                        function onDroneYChanged() { if (!canvas2DTimer.running) canvas2DTimer.start() }
                        function onTargetXChanged() { if (!canvas2DTimer.running) canvas2DTimer.start() }
                        function onTargetYChanged() { if (!canvas2DTimer.running) canvas2DTimer.start() }
                        function onDistanceToTargetChanged() { if (!canvas2DTimer.running) canvas2DTimer.start() }
                    }
                }

                        Text {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 10
                            text: "2D 俯视图"
                            font.pixelSize: 11
                            font.bold: true
                            color: primaryColor
                        }

                        // 底部信息栏
                        Row {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 15
                            spacing: 15

                            // 飞机位置信息
                            Rectangle {
                                width: 200
                                height: 120
                                color: Qt.rgba(0, 0, 0, 0.7)
                                border.color: Qt.rgba(primaryColor.r, primaryColor.g, primaryColor.b, 0.5)
                                border.width: 1
                                radius: 4

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 5

                                    Text {
                                        text: "飞机位置 (NED)"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: primaryColor
                                    }
                                    Text {
                                        text: "X: " + missionState.droneX.toFixed(1) + " m"
                                        font.pixelSize: 10
                                        color: textColor
                                    }
                                    Text {
                                        text: "Y: " + missionState.droneY.toFixed(1) + " m"
                                        font.pixelSize: 10
                                        color: textColor
                                    }
                                    Text {
                                        text: "Z: " + missionState.droneZ.toFixed(1) + " m"
                                        font.pixelSize: 10
                                        color: textColor
                                    }
                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: Qt.rgba(primaryColor.r, primaryColor.g, primaryColor.b, 0.3)
                                    }
                                    Text {
                                        text: "缩放: " + parent.parent.parent.parent.viewScale.toFixed(1) + "x"
                                        font.pixelSize: 9
                                        color: textColorDim
                                    }
                                }
                            }

                            // 操作提示
                            Rectangle {
                                width: 220
                                height: 120
                                color: Qt.rgba(0, 0, 0, 0.7)
                                border.color: Qt.rgba(primaryColor.r, primaryColor.g, primaryColor.b, 0.5)
                                border.width: 1
                                radius: 4

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 3

                                    Text {
                                        text: "操作提示"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: primaryColor
                                    }
                                    Text {
                                        text: "• 左键拖动：旋转/平移"
                                        font.pixelSize: 9
                                        color: textColor
                                    }
                                    Text {
                                        text: "• 滚轮：缩放视图"
                                        font.pixelSize: 9
                                        color: textColor
                                    }
                                    Text {
                                        text: "• 双击：重置视图"
                                        font.pixelSize: 9
                                        color: textColor
                                    }
                                    Text {
                                        text: "• 上方：3D轨迹视图"
                                        font.pixelSize: 9
                                        color: textColor
                                    }
                                    Text {
                                        text: "• 下方：2D俯视图"
                                        font.pixelSize: 9
                                        color: textColor
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // 右侧：控制面板 (30%)
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.3
                color: panelColor

                Flickable {
                    anchors.fill: parent
                    contentHeight: controlColumn.height
                    clip: true

                    Column {
                        id: controlColumn
                        width: parent.width
                        spacing: 12
                        padding: 15

                        // 1. 目标设置卡
                        ControlCard {
                            title: "目标坐标 (NED)"

                            Column {
                                width: parent.width
                                spacing: 8

                                // X坐标
                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        text: "X(北):"
                                        color: textColor
                                        font.pixelSize: 11
                                        width: 50
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    TextField {
                                        width: parent.width - 70
                                        height: 32
                                        text: missionState.targetX.toFixed(1)
                                        onEditingFinished: missionState.targetX = parseFloat(text)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: 11
                                        background: Rectangle {
                                            color: controlColor
                                            border.color: parent.activeFocus ? primaryColor : Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.3)
                                            border.width: 1
                                        }
                                        color: textColor
                                    }
                                    Text {
                                        text: "m"
                                        color: textColorDim
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                // Y坐标
                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        text: "Y(东):"
                                        color: textColor
                                        font.pixelSize: 11
                                        width: 50
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    TextField {
                                        width: parent.width - 70
                                        height: 32
                                        text: missionState.targetY.toFixed(1)
                                        onEditingFinished: missionState.targetY = parseFloat(text)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: 11
                                        background: Rectangle {
                                            color: controlColor
                                            border.color: parent.activeFocus ? primaryColor : Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.3)
                                            border.width: 1
                                        }
                                        color: textColor
                                    }
                                    Text {
                                        text: "m"
                                        color: textColorDim
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                // Z坐标
                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        text: "Z(下):"
                                        color: textColor
                                        font.pixelSize: 11
                                        width: 50
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    TextField {
                                        width: parent.width - 70
                                        height: 32
                                        text: missionState.targetZ.toFixed(1)
                                        onEditingFinished: missionState.targetZ = parseFloat(text)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: 11
                                        background: Rectangle {
                                            color: controlColor
                                            border.color: parent.activeFocus ? primaryColor : Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.3)
                                            border.width: 1
                                        }
                                        color: textColor
                                    }
                                    Text {
                                        text: "m"
                                        color: textColorDim
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }

                        // 2. 打击约束卡
                        ControlCard {
                            title: "打击约束设置"

                            Column {
                                width: parent.width
                                spacing: 10

                                Row {
                                    width: parent.width
                                    spacing: 8

                                    Repeater {
                                        model: [
                                            {text: "无约束", icon: "━"},
                                            {text: "垂直", icon: "↓"},
                                            {text: "水平", icon: "→"}
                                        ]

                                        Button {
                                            width: (parent.parent.width - 16) / 3
                                            height: 50

                                            background: Rectangle {
                                                color: missionState.constraintMode === index ? primaryColor : controlColor
                                                border.color: primaryColor
                                                border.width: 1
                                                radius: 4
                                            }

                                            contentItem: Column {
                                                spacing: 4
                                                anchors.centerIn: parent
                                                Text {
                                                    text: modelData.icon
                                                    font.pixelSize: 18
                                                    font.bold: true
                                                    color: missionState.constraintMode === index ? "#000000" : primaryColor
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                }
                                                Text {
                                                    text: modelData.text
                                                    font.pixelSize: 10
                                                    color: missionState.constraintMode === index ? "#000000" : textColor
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                }
                                            }

                                            onClicked: missionState.constraintMode = index
                                        }
                                    }
                                }

                            Column {
                                width: parent.width
                                spacing: 8
                                visible: missionState.constraintMode === 1

                                Row {
                                    width: parent.width
                                    spacing: 8

                                    Text {
                                        text: "垂直碰撞角:"
                                        color: textColor
                                        font.pixelSize: 11
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    TextField {
                                        width: 60
                                        text: missionState.impactAngleV.toFixed(0)
                                        onEditingFinished: missionState.impactAngleV = parseFloat(text)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: 11
                                        background: Rectangle {
                                            color: controlColor
                                            border.color: parent.activeFocus ? primaryColor : Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.3)
                                            border.width: 1
                                        }
                                        color: textColor
                                    }

                                    Text {
                                        text: "°"
                                        color: textColorDim
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Slider {
                                    width: parent.width
                                    from: -180
                                    to: 0
                                    value: missionState.impactAngleV
                                    onValueChanged: missionState.impactAngleV = value

                                    background: Rectangle {
                                        x: parent.leftPadding
                                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                        width: parent.availableWidth
                                        height: 4
                                        color: controlColor
                                        radius: 2

                                        Rectangle {
                                            width: parent.parent.visualPosition * parent.width
                                            height: parent.height
                                            color: primaryColor
                                            radius: 2
                                        }
                                    }

                                    handle: Rectangle {
                                        x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                        width: 16
                                        height: 16
                                        radius: 8
                                        color: primaryColor
                                        border.color: "#FFFFFF"
                                        border.width: 2
                                    }
                                }
                            }
                            }
                        }

                        // 3. 性能参数卡
                        ControlCard {
                            title: "性能限制"

                            Column {
                                width: parent.width
                                spacing: 8

                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        text: "最大速度"
                                        color: textColor
                                        font.pixelSize: 11
                                        width: 70
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    TextField {
                                        width: parent.width - 110
                                        height: 32
                                        text: missionState.maxVelocity.toFixed(1)
                                        onEditingFinished: missionState.maxVelocity = parseFloat(text)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: 11
                                        background: Rectangle {
                                            color: controlColor
                                            border.color: parent.activeFocus ? primaryColor : Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.3)
                                            border.width: 1
                                        }
                                        color: textColor
                                    }
                                    Text {
                                        text: "m/s"
                                        color: textColorDim
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        text: "最大加速度"
                                        color: textColor
                                        font.pixelSize: 11
                                        width: 70
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    TextField {
                                        width: parent.width - 110
                                        height: 32
                                        text: missionState.maxAcceleration.toFixed(1)
                                        onEditingFinished: missionState.maxAcceleration = parseFloat(text)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: 11
                                        background: Rectangle {
                                            color: controlColor
                                            border.color: parent.activeFocus ? primaryColor : Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.3)
                                            border.width: 1
                                        }
                                        color: textColor
                                    }
                                    Text {
                                        text: "m/s²"
                                        color: textColorDim
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        text: "命中距离"
                                        color: textColor
                                        font.pixelSize: 11
                                        width: 70
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    TextField {
                                        width: parent.width - 110
                                        height: 32
                                        text: missionState.missDistance.toFixed(1)
                                        onEditingFinished: missionState.missDistance = parseFloat(text)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: 11
                                        background: Rectangle {
                                            color: controlColor
                                            border.color: parent.activeFocus ? primaryColor : Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.3)
                                            border.width: 1
                                        }
                                        color: textColor
                                    }
                                    Text {
                                        text: "m"
                                        color: textColorDim
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }

                        // 4. 快速预设卡
                        ControlCard {
                            title: "快速打击模式"

                            Column {
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: [
                                        {text: "垂直俯冲", angle: -90},
                                        {text: "45°倾斜", angle: -45},
                                        {text: "水平打击", angle: 0}
                                    ]

                                    Button {
                                        width: parent.width
                                        height: 40

                                        background: Rectangle {
                                            color: parent.pressed ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.3) :
                                                   (Math.abs(missionState.impactAngleV - modelData.angle) < 1 ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.2) : controlColor)
                                            border.color: accentColor
                                            border.width: 1
                                            radius: 4
                                        }

                                        contentItem: Text {
                                            text: modelData.text
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: textColor
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: {
                                            missionState.constraintMode = 1
                                            missionState.impactAngleV = modelData.angle
                                        }
                                    }
                                }
                            }
                        }

                        // 5. 任务状态卡
                        ControlCard {
                            title: "任务状态"

                            Column {
                                width: parent.width
                                spacing: 8

                                Rectangle {
                                    width: parent.width
                                    height: 40
                                    color: controlColor
                                    border.width: 2
                                    radius: 4

                                    function getStatusColor() {
                                        switch(missionState.status) {
                                            case "IDLE": return textColorDim
                                            case "ENGAGING": return secondaryColor
                                            case "PULLUP": return warningColor
                                            case "COMPLETE": return primaryColor
                                            default: return textColor
                                        }
                                    }

                                    border.color: getStatusColor()

                                    Text {
                                        anchors.centerIn: parent
                                        text: missionState.status
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: parent.getStatusColor()
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 5

                                    Row {
                                        width: parent.width
                                        Text {
                                            text: "距离目标:"
                                            color: textColorDim
                                            font.pixelSize: 10
                                            width: 70
                                        }
                                        Text {
                                            text: missionState.distanceToTarget.toFixed(1) + " m"
                                            color: textColor
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        Text {
                                            text: "视线角:"
                                            color: textColorDim
                                            font.pixelSize: 10
                                            width: 70
                                        }
                                        Text {
                                            text: missionState.losAngle.toFixed(1) + " °"
                                            color: textColor
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        Text {
                                            text: "前置角:"
                                            color: textColorDim
                                            font.pixelSize: 10
                                            width: 70
                                        }
                                        Text {
                                            text: missionState.leadAngle.toFixed(1) + " °"
                                            color: textColor
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }

                        // 6. 执行控制卡
                        ControlCard {
                            title: "执行控制"

                            Column {
                                width: parent.width
                                spacing: 8

                                Button {
                                    width: parent.width
                                    height: 45
                                    text: "开始任务"
                                    enabled: missionState.status === "IDLE"

                                    background: Rectangle {
                                        color: parent.enabled ? secondaryColor : Qt.rgba(secondaryColor.r, secondaryColor.g, secondaryColor.b, 0.3)
                                        border.width: 0
                                        radius: 4
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: parent.enabled ? "#000000" : textColorDim
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: executeStrike()
                                }

                                Button {
                                    width: parent.width
                                    height: 40
                                    text: "重置参数"

                                    background: Rectangle {
                                        color: parent.pressed ? Qt.rgba(0.5, 0.5, 0.5, 0.3) : controlColor
                                        border.color: textColorDim
                                        border.width: 1
                                        radius: 4
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        font.pixelSize: 12
                                        color: textColor
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: resetParameters()
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.3)
                                }

                                Button {
                                    width: parent.width
                                    height: 50
                                    text: "中止任务"
                                    enabled: missionState.status !== "IDLE"

                                    background: Rectangle {
                                        color: parent.enabled ? dangerColor : Qt.rgba(dangerColor.r, dangerColor.g, dangerColor.b, 0.3)
                                        border.width: 0
                                        radius: 4
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: parent.enabled ? "#000000" : textColorDim
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: abortMission()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 自定义控制卡片组件
    component ControlCard: Rectangle {
        property string title: ""
        default property alias children: contentItem.children

        width: parent ? parent.width : 300
        implicitHeight: contentColumn.implicitHeight + 20
        height: implicitHeight
        color: Qt.rgba(0, 0, 0, 0.3)
        border.color: Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0.3)
        border.width: 1
        radius: 6

        Column {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 10

            Text {
                text: title
                font.pixelSize: 12
                font.bold: true
                color: primaryColor
                width: parent.width
            }

            Item {
                id: contentItem
                width: parent.width
                implicitHeight: childrenRect.height
                height: implicitHeight
            }
        }
    }

    // 计算距离
    function calculateDistance() {
        var dx = missionState.targetX - missionState.droneX
        var dy = missionState.targetY - missionState.droneY
        var dz = missionState.targetZ - missionState.droneZ
        missionState.distanceToTarget = Math.sqrt(dx*dx + dy*dy + dz*dz)
    }

    // 执行打击
    function executeStrike() {
        console.log("执行定点打击:")
        console.log("  目标: X=" + missionState.targetX + " Y=" + missionState.targetY + " Z=" + missionState.targetZ)
        console.log("  约束模式: " + missionState.constraintMode)
        console.log("  碰撞角: " + missionState.impactAngleV + "°")

        // TODO: 发送 MAVLink 命令
        // param set PN_CONSTR_MODE missionState.constraintMode
        // param set PN_IMPACT_ANG_V missionState.impactAngleV
        // param set PN_MAX_VEL missionState.maxVelocity
        // param set PN_MAX_ACCEL missionState.maxAcceleration
        // proportional_navigation engage X Y Z

        missionState.status = "ENGAGING"
    }

    // 中止任务
    function abortMission() {
        console.log("中止定点打击任务")
        // TODO: proportional_navigation abort
        missionState.status = "IDLE"
        missionState.distanceToTarget = 0.0
        missionState.losAngle = 0.0
        missionState.leadAngle = 0.0
    }

    // 重置参数
    function resetParameters() {
        missionState.targetX = 50.0
        missionState.targetY = 30.0
        missionState.targetZ = -10.0
        missionState.constraintMode = 1
        missionState.impactAngleV = -90.0
        missionState.maxVelocity = 28.0
        missionState.maxAcceleration = 15.0
        missionState.missDistance = 2.0
        missionState.pullupEnabled = false
    }

    // 定时器：更新状态
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            calculateDistance()
            // TODO: 从 PX4 获取实时状态数据
        }
    }
}
