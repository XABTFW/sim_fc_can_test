// Mavlinktest.cpp
#include "Mavlinktest.h"
#include "QGCApplication.h"
#include "MultiVehicleManager.h"
#include "MAVLinkProtocol.h"
#include "Vehicle.h"
#include <QDebug>
#include "mavlink_msg_swarm_mission_item.h"

Mavlinktest::Mavlinktest(QObject *parent)
    : QAbstractListModel(parent), _cursor_home_pos(-1), _cursor(0)
{
    // 获取全局唯一 MultiVehicleManager 和 MAVLinkProtocol 实例
    MultiVehicleManager* manager = MultiVehicleManager::instance();
    connect(manager, &MultiVehicleManager::activeVehicleChanged, this, &Mavlinktest::_setActiveVehicle);
    _setActiveVehicle(manager->activeVehicle());

    MAVLinkProtocol* mavlinkProtocol = MAVLinkProtocol::instance();
    connect(mavlinkProtocol, &MAVLinkProtocol::messageReceived, this, &Mavlinktest::_receiveMessage);
}

Mavlinktest::~Mavlinktest()
{
    if (_vehicle) {
        QByteArray msg;
        _sendSerialData(msg, true);
    }
}

int Mavlinktest::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    return _lines.count();
}

QVariant Mavlinktest::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= _lines.size()) return QVariant();
    if (role == TextRole) return _lines[index.row()];
    return QVariant();
}

QHash<int, QByteArray> Mavlinktest::roleNames() const
{
    return {{TextRole, "text"}};
}

void Mavlinktest::sendCommand(QString command)
{
    _history.append(command);
    command.append("\n");
    _sendSerialData(qPrintable(command));
    _cursor_home_pos = -1;
    _cursor = rowCount();
}

QString Mavlinktest::historyUp(const QString& current)
{
    return _history.up(current);
}

QString Mavlinktest::historyDown(const QString& current)
{
    return _history.down(current);
}

void Mavlinktest::_setActiveVehicle(Vehicle* vehicle)
{
    for (const auto &con : _uas_connections) disconnect(con);
    _uas_connections.clear();
    _vehicle = vehicle;

    if (_vehicle) {
        _incoming_buffer.clear();
        beginResetModel();
        _lines.clear();
        endResetModel();
        _cursor = 0;
        _cursor_home_pos = -1;
        _uas_connections << connect(_vehicle, &Vehicle::mavlinkSerialControl, this, &Mavlinktest::_receiveData);
    }
}

void Mavlinktest::_receiveData(uint8_t device, uint8_t, uint16_t, uint32_t, QByteArray data)
{
    if (device != SERIAL_CONTROL_DEV_SHELL) return;
    _incoming_buffer.append(data);

    while (!_incoming_buffer.isEmpty()) {
        bool newline = false;
        int idx = _incoming_buffer.indexOf('\n');
        if (idx == -1) idx = _incoming_buffer.size();
        else newline = true;

        QByteArray fragment = _incoming_buffer.mid(0, idx);
        if (_processANSItext(fragment)) {
            writeLine(_cursor, fragment);
            if (newline) _cursor++;
            _incoming_buffer.remove(0, idx + (newline ? 1 : 0));
        } else return;
    }
}

void Mavlinktest::_receiveMessage(LinkInterface*, mavlink_message_t message)
{
    if (message.msgid == MAVLINK_MSG_ID_UAV_INFO) {
        mavlink_uav_info_t mavlink_uavinfo;
        mavlink_msg_uav_info_decode(&message, &mavlink_uavinfo);

        _test1 = QString::number(mavlink_uavinfo.mavid); emit test1Changed();
        _test2 = QString::number(mavlink_uavinfo.yaw); emit test2Changed();
        _test3 = QString::number(mavlink_uavinfo.rel_alt); emit test3Changed();
    }

    // ========== 转发 SWARM_MISSION_ITEM 消息给所有飞机 ==========
    if (message.msgid == MAVLINK_MSG_ID_SWARM_MISSION_ITEM) {
        mavlink_swarm_mission_item_t swarm_item;
        mavlink_msg_swarm_mission_item_decode(&message, &swarm_item);

        // 获取所有连接的飞机
        QMap<int, Vehicle*> vehicles = MultiVehicleManager::instance()->my_vehicles();

        for (auto it = vehicles.begin(); it != vehicles.end(); ++it) {
            Vehicle* vehicle = it.value();
            if (!vehicle) continue;

            // 不转发给发送者自己
            if (vehicle->id() == swarm_item.leader_id) continue;

            WeakLinkInterfacePtr weakLink = vehicle->vehicleLinkManager()->primaryLink();
            if (weakLink.expired()) continue;

            SharedLinkInterfacePtr sharedLink = weakLink.lock();
            if (!sharedLink) continue;

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

void Mavlinktest::_sendcom(QString test1, QString test2, QString test3)
{
    qDebug() << "[_sendcom] Sending test1:" << test1 << " test2:" << test2 << " test3:" << test3;

    if (!_vehicle) return;

    auto weakLink = _vehicle->vehicleLinkManager()->primaryLink();
    if (!weakLink.expired()) {
        auto sharedLink = weakLink.lock();
        if (!sharedLink) return;

        uint8_t send_test1 = test1.toUInt();
        int16_t send_test2 = test2.toShort();
        float send_test3 = test3.toFloat();

        mavlink_message_t msg;
        //mavlink_msg_test_mavlink_pack_chan(_vehicle->id(), 1, sharedLink->mavlinkChannel(), &msg, send_test1, send_test2, send_test3);

        mavlink_msg_uav_info_pack_chan(_vehicle->id(), 1, sharedLink->mavlinkChannel(), &msg,
            1,          // mavid
            0,          // group_id
            0,          // is_leader
            47.89f,     // lat
            6.66f,      // lon
            5.0f,       // yaw
            5.0f,       // yaw_speed
            6.0f,       // rel_alt
            6.0f,       // vx
            7.0f,       // vy
            7.0f,       // vz
            0);         // land
       // _vehicle->sendMessageOnLinkThreadSafe(sharedLink.get(), msg);

    }
}

void Mavlinktest::_sendSerialData(QByteArray data, bool close)
{
    if (!_vehicle) return;

    auto weakLink = _vehicle->vehicleLinkManager()->primaryLink();
    if (!weakLink.expired()) {
        auto sharedLink = weakLink.lock();
        if (!sharedLink) return;

        Q_UNUSED(data);
        Q_UNUSED(close);
    }
}

bool Mavlinktest::_processANSItext(QByteArray &line)
{
    for (int i = 0; i < line.size(); i++) {
        if (line.at(i) == '\x1B') {
            if (i < line.size() - 2 && line.at(i + 1) == '[') {
                switch (line.at(i + 2)) {
                    case 'H':
                        _cursor_home_pos = (_cursor_home_pos == -1) ? _cursor : _cursor_home_pos;
                        _cursor = _cursor_home_pos;
                        break;
                    case 'K':
                        if (_cursor < _lines.size()) _lines[_cursor] = "";
                        break;
                    case '2':
                        if (i >= line.size() - 3) return false;
                        if (line.at(i + 3) == 'J' && _cursor_home_pos != -1) {
                            for (int j = _cursor_home_pos; j < _lines.size(); ++j) _lines[j] = "";
                        }
                        line.remove(i + 3, 1);
                        break;
                    default: continue;
                }
                line.remove(i, 3);
                i--;
            } else return false;
        }
    }
    return true;
}

void Mavlinktest::writeLine(int line, const QByteArray &text)
{
    while (line >= _lines.size()) {
        beginInsertRows(QModelIndex(), _lines.size(), _lines.size());
        _lines.append("");
        endInsertRows();
    }

    _lines[line] += text;
    emit dataChanged(index(line), index(line), {TextRole});
}

void Mavlinktest::CommandHistory::append(const QString& command)
{
    if (!command.isEmpty() && (_history.isEmpty() || _history.last() != command)) {
        if (_history.size() >= maxHistoryLength) _history.removeFirst();
        _history.append(command);
    }
    _index = _history.size();
}

QString Mavlinktest::CommandHistory::up(const QString& current)
{
    if (_index <= 0) return current;
    --_index;
    return (_index < _history.size()) ? _history[_index] : "";
}

QString Mavlinktest::CommandHistory::down(const QString& current)
{
    if (_index >= _history.size()) return current;
    ++_index;
    return (_index < _history.size()) ? _history[_index] : "";
}
