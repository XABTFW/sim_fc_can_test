/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "PX4CANTestController.h"
#include "MAVLinkProtocol.h"
#include "MultiVehicleManager.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

#include <QByteArray>
#include <QDebug>
#include <QStringList>

PX4CANTestController::PX4CANTestController(QObject* parent)
    : QObject(parent)
{
    _mavlink = MAVLinkProtocol::instance();
    MultiVehicleManager* manager = MultiVehicleManager::instance();
    (void) connect(manager, &MultiVehicleManager::activeVehicleChanged, this, &PX4CANTestController::_setActiveVehicle);
    _setActiveVehicle(manager->activeVehicle());

    qDebug() << "PX4CANTestController created";
}

PX4CANTestController::~PX4CANTestController()
{
    qDebug() << "PX4CANTestController destroyed";
}

void PX4CANTestController::sendCANData(const QString& data)
{
    const QStringList parts = data.split(':');
    if (parts.size() != 2) {
        qWarning() << "Invalid format, expected: frameId:hexData";
        return;
    }

    const QString frameId = parts[0].trimmed();
    const QString hexData = parts[1].trimmed();

    if (_sendShellCommand(QStringLiteral("can_test_link send %1 %2").arg(frameId, hexData))) {
        emit canDataSent(QString("ID=%1 Data=[%2]").arg(frameId, hexData));
    }
}

void PX4CANTestController::startReceive(const QString& device)
{
    const QString trimmedDevice = device.trimmed().isEmpty() ? QStringLiteral("can0") : device.trimmed();

    if (_sendShellCommand(QStringLiteral("can_test_link start -m rx -d %1").arg(trimmedDevice))) {
        _setRole(Role::Receive);
    }
}

void PX4CANTestController::stopReceive()
{
    if (_role == Role::Receive && _sendShellCommand(QStringLiteral("can_test_link stop"))) {
        _setRole(Role::Idle);
    }
}

bool PX4CANTestController::_sendShellCommand(const QString& command)
{
    if (!_vehicle) {
        qWarning() << "No active vehicle";
        return false;
    }

    auto primaryLink = _vehicle->vehicleLinkManager()->primaryLink().lock();
    if (!primaryLink) {
        qWarning() << "No primary link";
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
            _vehicle->id(),
            _vehicle->defaultComponentId());

        if (!_vehicle->sendMessageOnLinkThreadSafe(primaryLink.get(), msg)) {
            return false;
        }

        (void) output.remove(0, dataSize);
    }

    return true;
}

void PX4CANTestController::_setActiveVehicle(Vehicle* vehicle)
{
    const bool vehicleChanged = (_vehicle != vehicle);

    if (_vehicle) {
        (void) disconnect(_vehicle, &Vehicle::textMessageReceived, this, &PX4CANTestController::_handleVehicleTextMessage);
    }

    _vehicle = vehicle;

    if (vehicleChanged) {
        _setRole(Role::Idle);
    }

    if (_vehicle) {
        (void) connect(_vehicle, &Vehicle::textMessageReceived, this, &PX4CANTestController::_handleVehicleTextMessage);
    }
}

void PX4CANTestController::_setRole(Role role)
{
    if (_role == role) {
        return;
    }

    _role = role;
    emit receiveRunningChanged(_role == Role::Receive);
}

void PX4CANTestController::_handleVehicleTextMessage(int sysid, int componentid, int severity, QString text, QString description)
{
    Q_UNUSED(componentid);
    Q_UNUSED(severity);
    Q_UNUSED(description);

    if (!_vehicle || sysid != _vehicle->id()) {
        return;
    }

    if (text.startsWith(QStringLiteral("RX["))) {
        emit canDataReceived(text);
    }
}
