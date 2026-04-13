#include "Mavlinktest2.h"
//#include "QGCApplication.h"
//#include "UAS.h"
#include "MAVLinkInspectorController.h"
#include "mavlink_msg_uav_info.h"
#include "mavlink_msg_swarm_operation_ack.h"
#include "mavlink_msg_swarm_mission_item.h"
#include "MultiVehicleManager.h"
#include <QtCharts/QLineSeries>
#include<iostream>
#include <QtConcurrent/QtConcurrent>

using namespace std;
Mavlinktest2::Mavlinktest2()
    : QStringListModel(),
      _cursor_home_pos{-1},
      _cursor{0},
      _vehicle{nullptr}
{
   // auto *manager = qgcApp()->toolbox()->multiVehicleManager();
    connect(MultiVehicleManager::instance(), &MultiVehicleManager::activeVehicleChanged, this, &Mavlinktest2::_setActiveVehicle);
    _setActiveVehicle(MultiVehicleManager::instance()->activeVehicle());
    MAVLinkProtocol* mavlinkProtocol = MAVLinkProtocol::instance();
    connect(mavlinkProtocol, &MAVLinkProtocol::messageReceived, this, &Mavlinktest2::_receiveMessage);
}

Mavlinktest2::~Mavlinktest2()
{
    if (_vehicle)
    {
        QByteArray msg;
        _sendSerialData(msg, true);
    }
}

void
Mavlinktest2::sendCommand(QString command)
{
    _history.append(command);
    command.append("\n");
    _sendSerialData(qPrintable(command));
    _cursor_home_pos = -1;
    _cursor = rowCount();
}

QString
Mavlinktest2::historyUp(const QString& current)
{
    return _history.up(current);
}

QString
Mavlinktest2::historyDown(const QString& current)
{
    return _history.down(current);
}

void
Mavlinktest2::_setActiveVehicle(Vehicle* vehicle)
{
    for (auto &con : _uas_connections)
    {
        disconnect(con);
    }
    _uas_connections.clear();

    _vehicle = vehicle;
    // 性能优化：移除调试日志
    if (_vehicle)
    {
        _incoming_buffer.clear();
        // Reset the model
        setStringList(QStringList());
        _cursor = 0;
        _cursor_home_pos = -1;
        _uas_connections << connect(_vehicle, &Vehicle::mavlinkSerialControl, this, &Mavlinktest2::_receiveData);
    }
}

void
Mavlinktest2::_receiveData(uint8_t device, uint8_t, uint16_t, uint32_t, QByteArray data)
{
    if (device != SERIAL_CONTROL_DEV_SHELL)
    {
        return;
    }
    // auto idx = index(_cursor);
    //setData(idx,  QString("%1 ttyS6 -> * [%2]").arg(QTime::currentTime().toString("HH:mm:ss.zzz")).arg(12));


            // Append incoming data and parse for ANSI codes
    _incoming_buffer.append(data);
    while(!_incoming_buffer.isEmpty())
    {
        bool newline = false;
        int idx = _incoming_buffer.indexOf('\n');
        if (idx == -1)
        {
            // Read the whole incoming buffer
            idx = _incoming_buffer.size();
        }
        else
        {
            newline = true;
        }

        QByteArray fragment = _incoming_buffer.mid(0, idx);
        if (_processANSItext(fragment))
        {
            writeLine(_cursor, fragment);
            if (newline)
            {
                _cursor++;
            }
            _incoming_buffer.remove(0, idx + (newline ? 1 : 0));
        }
        else
        {
            // ANSI processing failed, need more data
            return;
        }
    }
}

void
Mavlinktest2::_receiveMessage(LinkInterface*, mavlink_message_t message)
{


    // if( message.msgid == MAVLINK_MSG_ID_ALTITUDE) {
    //     qDebug()<<"message.msgid"<<MAVLINK_MSG_ID_ALTITUDE<<__LINE__;
    // }
    //  qDebug()<<message.msgid<<MAVLINK_MSG_ID_TEST_MAVLINK;

    // 处理SWARM_OPERATION_ACK消息
    if(message.msgid == MAVLINK_MSG_ID_SWARM_OPERATION_ACK)
    {
        mavlink_swarm_operation_ack_t ack;
        mavlink_msg_swarm_operation_ack_decode(&message, &ack);

        // 格式化消息文本
        QString msgText;
        QString resultStr = (ack.result == 0) ? "成功" : "失败";

        switch (ack.operation_type) {
            case 1: // GROUP_CHANGE
                if (ack.result == 0) {
                    msgText = QString("飞机%1: 组号从%2切换到%3 成功")
                              .arg(ack.target_system)
                              .arg(ack.old_value)
                              .arg(ack.new_value);
                } else {
                    msgText = QString("飞机%1: 组号切换失败").arg(ack.target_system);
                }
                break;
            case 2: // LEADER_CHANGE
                if (ack.result == 0) {
                    QString oldRole = (ack.old_value == 1) ? "主机" : "从机";
                    QString newRole = (ack.new_value == 1) ? "主机" : "从机";
                    msgText = QString("飞机%1: 角色从%2切换到%3 成功")
                              .arg(ack.target_system)
                              .arg(oldRole)
                              .arg(newRole);
                } else {
                    msgText = QString("飞机%1: 角色切换失败").arg(ack.target_system);
                }
                break;
            case 3: // TAKEOFF
                msgText = QString("飞机%1 (第%2组): 起飞%3")
                          .arg(ack.target_system)
                          .arg(ack.new_value)
                          .arg(resultStr);
                break;
            case 4: // LAND
                msgText = QString("飞机%1 (第%2组): 降落%3")
                          .arg(ack.target_system)
                          .arg(ack.new_value)
                          .arg(resultStr);
                break;
            case 5: // PAUSE
                msgText = QString("飞机%1 (第%2组): 暂停%3")
                          .arg(ack.target_system)
                          .arg(ack.new_value)
                          .arg(resultStr);
                break;
            case 6: // CONTINUE
                msgText = QString("飞机%1 (第%2组): 继续%3")
                          .arg(ack.target_system)
                          .arg(ack.new_value)
                          .arg(resultStr);
                break;
            default:
                msgText = QString("飞机%1: 未知操作类型%2")
                          .arg(ack.target_system)
                          .arg(ack.operation_type);
                break;
        }

        // 性能优化：移除调试日志，只在错误时输出
        if (ack.result != 0) {
            qDebug() << "[Mavlinktest2] 操作失败:" << msgText;
        }

        // 发送信号通知QML
        emit swarmOperationAckReceived(
            ack.target_system,
            ack.operation_type,
            ack.result,
            ack.old_value,
            ack.new_value,
            msgText
        );

        return;
    }

    if(message.msgid==MAVLINK_MSG_ID_UAV_INFO)
    {
        if(!_vehicle)return;
        WeakLinkInterfacePtr weakLink = _vehicle->vehicleLinkManager()->primaryLink();

        if (!weakLink.expired()) {
            SharedLinkInterfacePtr sharedLink = weakLink.lock();

            if (!sharedLink) {
                qCDebug(VehicleLog) << "_handlePing: primary link gone!";
                return;
            }
            auto priority_link =sharedLink;


            mavlink_uav_info_t mavlink_uavinfo;
            mavlink_message_t msg;
            mavlink_msg_uav_info_decode(&message, &mavlink_uavinfo);
            mavlink_msg_uav_info_pack_chan(static_cast<uint8_t>(MAVLinkProtocol::instance()->getSystemId()),
                                           static_cast<uint8_t>(MAVLinkProtocol::getComponentId()),
                                           priority_link->mavlinkChannel(),
                                           &msg,
                                           mavlink_uavinfo.mavid,
                                           mavlink_uavinfo.group_id,
                                           mavlink_uavinfo.is_leader,
                                           mavlink_uavinfo.lat, mavlink_uavinfo.lon,
                                           mavlink_uavinfo.yaw, mavlink_uavinfo.yaw_speed,
                                           mavlink_uavinfo.rel_alt, mavlink_uavinfo.vx, mavlink_uavinfo.vy,
                                           mavlink_uavinfo.vz, mavlink_uavinfo.land);



            _vehicle->sendMessageOnLinkThreadSafe(sharedLink.get(), msg);
        }

    }

    // ========== 转发 SWARM_MISSION_ITEM 消息给所有飞机 ==========
    // 性能优化：移除调试日志，防止消息循环
    if(message.msgid == MAVLINK_MSG_ID_SWARM_MISSION_ITEM)
    {
        mavlink_swarm_mission_item_t swarm_item;
        mavlink_msg_swarm_mission_item_decode(&message, &swarm_item);

        // 防止消息循环：检查消息是否来自地面站自己
        if (message.sysid == MAVLinkProtocol::instance()->getSystemId()) {
            // 这是地面站自己转发的消息，不再转发，避免循环
            return;
        }

        // 获取所有连接的飞机
        QMap<int, Vehicle*> vehicles = MultiVehicleManager::instance()->my_vehicles();

        for (auto it = vehicles.begin(); it != vehicles.end(); ++it) {
            Vehicle* vehicle = it.value();
            if (!vehicle) continue;

            // 不转发给发送者自己
            if (vehicle->id() == swarm_item.leader_id) {
                continue;
            }

            WeakLinkInterfacePtr weakLink = vehicle->vehicleLinkManager()->primaryLink();
            if (weakLink.expired()) {
                continue;
            }

            SharedLinkInterfacePtr sharedLink = weakLink.lock();
            if (!sharedLink) {
                continue;
            }

            mavlink_message_t msg;
            mavlink_msg_swarm_mission_item_pack_chan(
                static_cast<uint8_t>(MAVLinkProtocol::instance()->getSystemId()),
                static_cast<uint8_t>(MAVLinkProtocol::getComponentId()),
                sharedLink->mavlinkChannel(),
                &msg,
                swarm_item.timestamp,
                swarm_item.group_id,
                swarm_item.leader_id,
                swarm_item.mission_id,
                swarm_item.total_count,
                swarm_item.current_seq,
                swarm_item.seq,
                swarm_item.nav_cmd,
                swarm_item.lat,
                swarm_item.lon,
                swarm_item.alt,
                swarm_item.yaw,
                swarm_item.acceptance_radius,
                swarm_item.loiter_radius,
                swarm_item.time_inside,
                swarm_item.autocontinue,
                swarm_item.sync_type
            );

            vehicle->sendMessageOnLinkThreadSafe(sharedLink.get(), msg);
        }
    }
}

void Mavlinktest2::set_main_airplane(int sysid, float x,float y,float z) {
    main_airplane = sysid;

    // 性能优化：移除调试日志
    vec_.clear();
    vec_.push_back(x);
    vec_.push_back(y);
    vec_.push_back(z);

    airplane_pos.clear();
    airplane_pos[sysid] = vec_;
}

void Mavlinktest2::caculate_pos(int sysid,float x,float y,float z){

    _vehicle = MultiVehicleManager::instance()->activeVehicle();
    // qDebug()<<x<<y<<z<<_vehicle->parameterManager()<<sysid;

    if(_vehicle->parameterManager() && sysid == _vehicle->id()) {
        _vehicle->parameterManager()->myswarm_param_send(sysid, "SWARM_X_OFFSET", FactMetaData::valueTypeFloat, x);
        _vehicle->parameterManager()->myswarm_param_send(sysid, "SWARM_Y_OFFSET", FactMetaData::valueTypeFloat, y);
        _vehicle->parameterManager()->myswarm_param_send(sysid, "SWARM_Z_OFFSET", FactMetaData::valueTypeFloat, z);
    }
}

//
void Mavlinktest2::_sendcom(uint8_t test1,uint8_t test2,uint8_t test3,uint32_t pause, uint32_t conti)
{
    if (!_vehicle)
    {
        qWarning() << "Internal error";
        return;
    }

    WeakLinkInterfacePtr weakLink = _vehicle->vehicleLinkManager()->primaryLink();
    if (!weakLink.expired()) {
        SharedLinkInterfacePtr sharedLink = weakLink.lock();

        if (!sharedLink) {
            qCDebug(VehicleLog) << "_handlePing: primary link gone!";
            return;
        }
        auto priority_link =sharedLink;

        mavlink_message_t msg;

        mavlink_msg_swarm_start_flag_pack_chan(static_cast<uint8_t>(MAVLinkProtocol::instance()->getSystemId()),
                                               static_cast<uint8_t>(MAVLinkProtocol::getComponentId()),
                                               priority_link->mavlinkChannel(),
                                               &msg,
                                               test1,
                                               test2,
                                               test3,pause,conti);

        _vehicle->sendMessageOnLinkThreadSafe(sharedLink.get(), msg);
        // 性能优化：移除调试日志
    }
}



void Mavlinktest2::_sendcom2(uint8_t test1,uint8_t test2,uint8_t test3,uint32_t pause, uint32_t conti) // 改为float
{
    if (!_vehicle)
    {
        qWarning() << "Internal error";
        return;
    }

    WeakLinkInterfacePtr weakLink = _vehicle->vehicleLinkManager()->primaryLink();
    if (!weakLink.expired()) {
        SharedLinkInterfacePtr sharedLink = weakLink.lock();

        if (!sharedLink) {
            qCDebug(VehicleLog) << "_handlePing: primary link gone!";
            return;
        }
        //            auto protocol = qgcApp()->toolbox()->mavlinkProtocol();
        auto priority_link =sharedLink;

        mavlink_uav_info_t mavlink_uavinfo;
        mavlink_message_t msg;
        mavlink_msg_uav_info_pack_chan(static_cast<uint8_t>(MAVLinkProtocol::instance()->getSystemId()),
                                       static_cast<uint8_t>(MAVLinkProtocol::getComponentId()),
                                       priority_link->mavlinkChannel(),
                                       &msg,
                                       mavlink_uavinfo.mavid,
                                       mavlink_uavinfo.group_id,
                                       mavlink_uavinfo.is_leader,
                                       mavlink_uavinfo.lat, mavlink_uavinfo.lon,
                                       mavlink_uavinfo.yaw, mavlink_uavinfo.yaw_speed,
                                       mavlink_uavinfo.rel_alt, mavlink_uavinfo.vx, mavlink_uavinfo.vy,
                                       mavlink_uavinfo.vz, mavlink_uavinfo.land);


                // QTimer::singleShot(100, this, [=]() {
                //     _vehicle->sendMessageOnLinkThreadSafe(sharedLink.get(), msg);
                // });




        _vehicle->sendMessageOnLinkThreadSafe(sharedLink.get(), msg);

    }
}


void
Mavlinktest2::_sendSerialData(QByteArray data, bool close)
{
    if (!_vehicle)
    {
        qWarning() << "Internal error";
        return;
    }

    WeakLinkInterfacePtr weakLink = _vehicle->vehicleLinkManager()->primaryLink();
    if (!weakLink.expired()) {
        SharedLinkInterfacePtr sharedLink = weakLink.lock();

        if (!sharedLink) {
            qCDebug(VehicleLog) << "_handlePing: primary link gone!";
            return;
        }


                // Send maximum sized chunks until the complete buffer is transmitted
                //        while(data.size())
                //        {
                //            QByteArray chunk{data.left(MAVLINK_MSG_SERIAL_CONTROL_FIELD_DATA_LEN)};
                //            uint8_t flags = SERIAL_CONTROL_FLAG_EXCLUSIVE |  SERIAL_CONTROL_FLAG_RESPOND | SERIAL_CONTROL_FLAG_MULTI;
                //            if (close)
                //            {
                //                flags = 0;
                //            }
                //            auto protocol = qgcApp()->toolbox()->mavlinkProtocol();
                //            auto priority_link =sharedLink;
                //            mavlink_message_t msg;



                //            mavlink_msg_serial_control_pack_chan(
                //                protocol->getSystemId(),
                //                protocol->getComponentId(),
                //                priority_link->mavlinkChannel(),
                //                &msg,
                //                SERIAL_CONTROL_DEV_SHELL,
                //                flags,
                //                0,
                //                0,
                //                chunk.size(),
                //                reinterpret_cast<uint8_t*>(chunk.data()));
                //            _vehicle->sendMessageOnLinkThreadSafe(sharedLink.get(), msg);
                //            data.remove(0, chunk.size());
                //        }
    }




}

bool
Mavlinktest2::_processANSItext(QByteArray &line)
{
    // Iterate over the incoming buffer to parse off known ANSI control codes
    for (int i = 0; i < line.size(); i++)
    {
        if (line.at(i) == '\x1B')
        {
            // For ANSI codes we expect at least 3 incoming chars
            if (i < line.size() - 2 && line.at(i+1) == '[')
            {
                // Parse ANSI code
                switch(line.at(i+2))
                {
                    default:
                        continue;
                    case 'H':
                        if (_cursor_home_pos == -1)
                        {
                            // Assign new home position if home is unset
                            _cursor_home_pos = _cursor;
                        }
                        else
                        {
                            // Rewind write cursor position to home
                            _cursor = _cursor_home_pos;
                        }
                        break;
                    case 'K':
                        // Erase the current line to the end
                        if (_cursor < rowCount())
                        {
                            setData(index(_cursor), "");
                        }
                        break;
                    case '2':
                        // Check for sufficient buffer size
                        if ( i >= line.size() - 3)
                        {
                            return false;
                        }

                        if (line.at(i+3) == 'J' && _cursor_home_pos != -1)
                        {
                            // Erase everything and rewind to home
                            bool blocked = blockSignals(true);
                            for (int j = _cursor_home_pos; j < rowCount(); j++)
                            {
                                setData(index(j), "");
                            }
                            blockSignals(blocked);
                            QVector<int> roles;
                            roles.reserve(2);
                            roles.append(Qt::DisplayRole);
                            roles.append(Qt::EditRole);
                            emit dataChanged(index(_cursor), index(rowCount()), roles);
                        }
                        // Even if we didn't understand this ANSI code, remove the 4th char
                        line.remove(i+3,1);
                        break;
                }
                // Remove the parsed ANSI code and decrement the bufferpos
                line.remove(i, 3);
                i--;
            }
            else
            {
                // We can reasonably expect a control code was fragemented
                // Stop parsing here and wait for it to come in
                return false;
            }
        }
    }
    return true;
}

void
Mavlinktest2::writeLine(int line, const QByteArray &text)
{
    auto rc = rowCount();
    if (line >= rc)
    {
        insertRows(rc, 1 + line - rc);
    }
    auto idx = index(line);
    setData(idx, data(idx, Qt::DisplayRole).toString() + text);
}

void Mavlinktest2::CommandHistory::append(const QString& command)
{
    if (command.length() > 0)
    {

        // do not append duplicates
        if (_history.length() == 0 || _history.last() != command)
        {

            if (_history.length() >= maxHistoryLength)
            {
                _history.removeFirst();
            }
            _history.append(command);
        }
    }
    _index = _history.length();
}

QString Mavlinktest2::CommandHistory::up(const QString& current)
{
    if (_index <= 0)
    {
        return current;
    }

    --_index;
    if (_index < _history.length())
    {
        return _history[_index];
    }
    return "";
}

QString Mavlinktest2::CommandHistory::down(const QString& current)
{
    if (_index >= _history.length())
    {
        return current;
    }

    ++_index;
    if (_index < _history.length())
    {
        return _history[_index];
    }
    return "";
}
