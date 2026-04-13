# PX4 CAN Test 与 QGC 集成指南

## 概述

can_test_link 是PX4端的CAN总线测试驱动，QGC需要通过MAVLink与其通信。

## 当前CAN数据格式

从 `can_test_link.cpp` 可以看到：

```cpp
struct can_frame frame = {};
frame.can_id = _tx_can_id & CAN_SFF_MASK;  // 标准帧ID (11位)
frame.can_dlc = 8;                          // 数据长度
frame.data[0] = 0x11;                       // 固定数据
frame.data[1] = 0x22;
// ...
frame.data[7] = 0x88;
```

**打印格式**:
```
TX[count]: ID=0x123 DLC=8 Data=[11 22 33 44 55 66 77 88]
RX[count]: ID=0x123 DLC=8 Data=[11 22 33 44 55 66 77 88]
```

## 实现方案

### 方案A：使用MAVLink TUNNEL消息（推荐）

**优点**: 不需要修改MAVLink协议，使用现有的TUNNEL消息
**缺点**: 需要定义自己的封装格式

#### 1. PX4端修改

在can_test_link中添加MAVLink支持：

```cpp
// 在 can_test_link.hpp 中添加
#include <uORB/Publication.hpp>
#include <uORB/Subscription.hpp>
#include <uORB/topics/vehicle_command.h>
#include <uORB/topics/vehicle_command_ack.h>

// 使用 VEHICLE_COMMAND 来接收QGC的指令
// MAV_CMD_USER_1 = 发送CAN帧
// param1 = CAN ID
// param2 = DLC
// param3-param6 = 数据 (每个float可以编码2个字节)
```

#### 2. QGC端实现

在 `PX4CANTestController.cc` 中：

```cpp
void PX4CANTestController::sendCANData(const QString& frameId, const QString& data)
{
    // 解析帧ID (支持0x123或123格式)
    bool ok;
    uint32_t canId = frameId.startsWith("0x") ?
        frameId.mid(2).toUInt(&ok, 16) :
        frameId.toUInt(&ok, 10);

    // 解析数据 (十六进制字符串，如 "11 22 33 44")
    QStringList dataBytes = data.split(' ', Qt::SkipEmptyParts);

    // 发送MAVLink COMMAND_LONG
    Vehicle* vehicle = qgcApp()->toolbox()->multiVehicleManager()->activeVehicle();
    if (vehicle) {
        vehicle->sendMavCommand(
            MAV_COMP_ID_AUTOPILOT1,
            MAV_CMD_USER_1,  // 自定义命令
            true,            // showError
            canId,           // param1: CAN ID
            dataBytes.size() // param2: DLC
            // param3-7: 数据字节
        );
    }
}
```

### 方案B：自定义MAVLink消息（更优雅）

**优点**: 类型安全，语义清晰
**缺点**: 需要修改MAVLink定义并重新编译

#### 1. 定义MAVLink消息

在 `mavlink/message_definitions/v1.0/common.xml` 或自定义dialect中添加：

```xml
<message id="12345" name="CAN_TEST_FRAME">
  <description>CAN test frame for debugging</description>
  <field type="uint32_t" name="can_id">CAN frame ID (11-bit standard)</field>
  <field type="uint8_t" name="dlc">Data length (0-8)</field>
  <field type="uint8_t[8]" name="data">CAN frame data</field>
  <field type="uint8_t" name="direction">0=TX, 1=RX</field>
  <field type="uint64_t" name="timestamp">Timestamp (microseconds)</field>
</message>
```

#### 2. PX4端实现

```cpp
// 订阅MAVLink CAN_TEST_FRAME消息
// 当收到direction=0(TX)时，发送CAN帧
// 当接收到CAN帧时，发送direction=1(RX)的MAVLink消息给QGC
```

#### 3. QGC端实现

```cpp
// 发送CAN帧
void PX4CANTestController::sendCANData(uint32_t canId, const QByteArray& data)
{
    mavlink_message_t msg;
    mavlink_can_test_frame_t frame;

    frame.can_id = canId;
    frame.dlc = data.size();
    memcpy(frame.data, data.constData(), qMin(8, data.size()));
    frame.direction = 0; // TX
    frame.timestamp = QDateTime::currentMSecsSinceEpoch() * 1000;

    mavlink_msg_can_test_frame_encode_chan(
        mavlink->getSystemId(),
        mavlink->getComponentId(),
        vehicle->priorityLink()->mavlinkChannel(),
        &msg,
        &frame
    );

    vehicle->sendMessageOnLink(vehicle->priorityLink(), msg);
}

// 接收CAN帧
void PX4CANTestController::_handleCANTestFrame(const mavlink_message_t& message)
{
    mavlink_can_test_frame_t frame;
    mavlink_msg_can_test_frame_decode(&message, &frame);

    if (frame.direction == 1) { // RX
        QString dataStr;
        for (int i = 0; i < frame.dlc; i++) {
            dataStr += QString("%1 ").arg(frame.data[i], 2, 16, QChar('0')).toUpper();
        }

        QString msg = QString("ID=0x%1 DLC=%2 Data=[%3]")
            .arg(frame.can_id, 3, 16, QChar('0'))
            .arg(frame.dlc)
            .arg(dataStr.trimmed());

        emit canDataReceived(msg);
    }
}
```

## 推荐实现路径

### 快速原型（使用VEHICLE_COMMAND）

1. **PX4端**: 修改can_test_link订阅vehicle_command
2. **QGC端**: 使用现有的sendMavCommand API
3. **优点**: 快速实现，无需修改MAVLink

### 生产版本（自定义MAVLink）

1. 在PX4的mavlink dialect中定义CAN_TEST_FRAME消息
2. 修改can_test_link支持MAVLink收发
3. 在QGC中实现完整的MAVLink处理
4. **优点**: 类型安全，易于维护

## 数据格式示例

### QGC发送格式
```
帧ID: 0x123
数据: 11 22 33 44 55 66 77 88
```

### PX4接收并发送CAN帧
```cpp
frame.can_id = 0x123;
frame.dlc = 8;
frame.data = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88};
```

### PX4接收CAN帧并报告给QGC
```
RX[1]: ID=0x123 DLC=8 Data=[11 22 33 44 55 66 77 88]
```

### QGC显示
```
[14:30:25] ID=0x123 DLC=8 Data=[11 22 33 44 55 66 77 88]
```

## 下一步

1. 选择实现方案（推荐先用VEHICLE_COMMAND快速原型）
2. 修改PX4端can_test_link添加MAVLink支持
3. 实现QGC端的PX4CANTestController
4. 测试端到端通信
