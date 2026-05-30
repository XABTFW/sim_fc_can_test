/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "VisualMavlinkTestController.h"
#include "MAVLinkProtocol.h"
#include "MultiVehicleManager.h"
#include "QmlObjectListModel.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

#include <QByteArray>
#include <QDebug>
#include <QStringList>

VisualMavlinkTestController::VisualMavlinkTestController(QObject* parent)
    : QObject(parent)
{
    _mavlink = MAVLinkProtocol::instance();
    _manager = MultiVehicleManager::instance();

    (void) connect(_manager, &MultiVehicleManager::vehicleAdded, this, &VisualMavlinkTestController::_vehiclesChanged);
    (void) connect(_manager, &MultiVehicleManager::vehicleRemoved, this, &VisualMavlinkTestController::_vehiclesChanged);

    _vehiclesChanged();

    qDebug() << "VisualMavlinkTestController created";
}

VisualMavlinkTestController::~VisualMavlinkTestController()
{
    qDebug() << "VisualMavlinkTestController destroyed";
}

void VisualMavlinkTestController::setSimVehicleId(int id)
{
    if (_simVehicleId != id) {
        _simVehicleId = id;
        emit simVehicleIdChanged();
    }
}

void VisualMavlinkTestController::setFcVehicleId(int id)
{
    if (_fcVehicleId != id) {
        _fcVehicleId = id;
        emit fcVehicleIdChanged();
    }
}

void VisualMavlinkTestController::startForward(int value)
{
    Vehicle* sim = _vehicleById(_simVehicleId);

    if (!sim) {
        qWarning() << "Forward test: simulation vehicle" << _simVehicleId << "not available";
        return;
    }

    _direction = Direction::Forward;

    if (_sendShellCommand(sim, QStringLiteral("visual_mavlink_test process %1 inc").arg(value))) {
        emit dataSent(QString("-> SIM(sysid=%1) value=%2 (inc)").arg(_simVehicleId).arg(value));
    }
}

void VisualMavlinkTestController::startReverse(int value)
{
    Vehicle* fc = _vehicleById(_fcVehicleId);

    if (!fc) {
        qWarning() << "Reverse test: flight controller vehicle" << _fcVehicleId << "not available";
        return;
    }

    _direction = Direction::Reverse;

    if (_sendShellCommand(fc, QStringLiteral("visual_mavlink_test process %1 dec").arg(value))) {
        emit dataSent(QString("-> FC(sysid=%1) value=%2 (dec)").arg(_fcVehicleId).arg(value));
    }
}

bool VisualMavlinkTestController::_sendShellCommand(Vehicle* vehicle, const QString& command)
{
    if (!vehicle) {
        qWarning() << "No vehicle for command" << command;
        return false;
    }

    auto primaryLink = vehicle->vehicleLinkManager()->primaryLink().lock();
    if (!primaryLink) {
        qWarning() << "No primary link for vehicle" << vehicle->id();
        return false;
    }

    QByteArray output(command.toUtf8());
    output.append('\n');

    while (!output.isEmpty()) {
        QByteArray chunk = output.left(MAVLINK_MSG_SERIAL_CONTROL_FIELD_DATA_LEN);
        const int dataSize = chunk.size();

        // MAVLink expects a fixed-size payload array.
        (void) chunk.append(MAVLINK_MSG_SERIAL_CONTROL_FIELD_DATA_LEN - dataSize, '\0');

        const uint8_t flags = SERIAL_CONTROL_FLAG_EXCLUSIVE | SERIAL_CONTROL_FLAG_RESPOND | SERIAL_CONTROL_FLAG_MULTI;

        mavlink_message_t msg{};
        (void) mavlink_msg_serial_control_pack_chan(
            _mavlink->getSystemId(),
            _mavlink->getComponentId(),
            primaryLink->mavlinkChannel(),
            &msg,
            SERIAL_CONTROL_DEV_SHELL,
            flags,
            0,
            0,
            dataSize,
            reinterpret_cast<uint8_t*>(chunk.data()),
            vehicle->id(),
            vehicle->defaultComponentId());

        if (!vehicle->sendMessageOnLinkThreadSafe(primaryLink.get(), msg)) {
            return false;
        }

        (void) output.remove(0, dataSize);
    }

    return true;
}

Vehicle* VisualMavlinkTestController::_vehicleById(int id) const
{
    if (id < 0 || !_manager) {
        return nullptr;
    }

    return _manager->getVehicleById(id);
}

void VisualMavlinkTestController::_connectVehicle(Vehicle* vehicle)
{
    if (!vehicle) {
        return;
    }

    _vehicleConnections.append(
        connect(vehicle, &Vehicle::textMessageReceived, this, &VisualMavlinkTestController::_handleVehicleTextMessage));
}

void VisualMavlinkTestController::_vehiclesChanged()
{
    // Reconnect text-message handling for the current set of vehicles.
    for (const QMetaObject::Connection& connection : _vehicleConnections) {
        (void) disconnect(connection);
    }

    _vehicleConnections.clear();

    QmlObjectListModel* vehicles = _manager ? _manager->vehicles() : nullptr;

    if (vehicles) {
        for (int i = 0; i < vehicles->count(); i++) {
            _connectVehicle(vehicles->value<Vehicle*>(i));
        }
    }

    _refreshVehicleIds();
}

void VisualMavlinkTestController::_refreshVehicleIds()
{
    QVariantList ids;
    QmlObjectListModel* vehicles = _manager ? _manager->vehicles() : nullptr;

    if (vehicles) {
        for (int i = 0; i < vehicles->count(); i++) {
            Vehicle* vehicle = vehicles->value<Vehicle*>(i);

            if (vehicle) {
                ids.append(vehicle->id());
            }
        }
    }

    _vehicleIds = ids;
    emit vehicleIdsChanged();

    // Provide sensible defaults: the lowest id is treated as the simulation
    // vehicle, a different id as the real flight controller.
    if (_simVehicleId < 0 && !ids.isEmpty()) {
        setSimVehicleId(ids.first().toInt());
    }

    if (_fcVehicleId < 0) {
        for (const QVariant& id : ids) {
            if (id.toInt() != _simVehicleId) {
                setFcVehicleId(id.toInt());
                break;
            }
        }
    }
}

bool VisualMavlinkTestController::_parseValue(const QString& text, const QString& tag, long& valueOut) const
{
    // Expected format: "VMT:<inc|dec>:<value>"
    const QString prefix = QStringLiteral("VMT:") + tag + QStringLiteral(":");

    if (!text.startsWith(prefix)) {
        return false;
    }

    bool ok = false;
    valueOut = text.mid(prefix.length()).trimmed().toLong(&ok);
    return ok;
}

void VisualMavlinkTestController::_handleVehicleTextMessage(int sysid, int componentid, int severity, QString text, QString description)
{
    Q_UNUSED(componentid);
    Q_UNUSED(severity);
    Q_UNUSED(description);

    if (!text.startsWith(QStringLiteral("VMT:"))) {
        return;
    }

    long incValue = 0;
    long decValue = 0;
    const bool isInc = _parseValue(text, QStringLiteral("inc"), incValue);
    const bool isDec = _parseValue(text, QStringLiteral("dec"), decValue);

    if (!isInc && !isDec) {
        return;
    }

    const long value = isInc ? incValue : decValue;
    const QString summary = QString("sysid=%1 %2").arg(sysid).arg(text);

    // Display the message in the appropriate window.
    if (sysid == _simVehicleId) {
        emit simDataReceived(summary);
    } else if (sysid == _fcVehicleId) {
        emit fcDataReceived(summary);
    } else {
        // Unknown source: show it on both for visibility.
        emit simDataReceived(summary);
        emit fcDataReceived(summary);
    }

    // Relay to the next hop according to the active test direction.
    if (_direction == Direction::Forward && isInc && sysid == _simVehicleId) {
        // 仿真 returned value, forward to the real flight controller.
        Vehicle* fc = _vehicleById(_fcVehicleId);

        if (fc && _sendShellCommand(fc, QStringLiteral("visual_mavlink_test process %1 inc").arg(value))) {
            emit dataSent(QString("-> FC(sysid=%1) value=%2 (inc)").arg(_fcVehicleId).arg(value));
        }

    } else if (_direction == Direction::Reverse && isDec && sysid == _fcVehicleId) {
        // 飞控 returned value, forward to the simulation.
        Vehicle* sim = _vehicleById(_simVehicleId);

        if (sim && _sendShellCommand(sim, QStringLiteral("visual_mavlink_test process %1 dec").arg(value))) {
            emit dataSent(QString("-> SIM(sysid=%1) value=%2 (dec)").arg(_simVehicleId).arg(value));
        }
    }
}
