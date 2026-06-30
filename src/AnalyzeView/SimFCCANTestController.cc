/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "SimFCCANTestController.h"

#include "MAVLinkProtocol.h"
#include "MultiVehicleManager.h"
#include "QmlObjectListModel.h"
#include "VehicleLinkManager.h"

#include <QByteArray>
#include <QRegularExpression>
#include <QStringList>

SimFCCANTestController::SimFCCANTestController(QObject* parent)
    : QObject(parent)
{
    _mavlink = MAVLinkProtocol::instance();
    _manager = MultiVehicleManager::instance();

    (void) connect(_manager, &MultiVehicleManager::vehicleAdded, this, &SimFCCANTestController::_vehiclesChanged);
    (void) connect(_manager, &MultiVehicleManager::vehicleRemoved, this, &SimFCCANTestController::_vehiclesChanged);

    _vehiclesChanged();
}

SimFCCANTestController::~SimFCCANTestController()
{
}

void SimFCCANTestController::setFcVehicleId(int id)
{
    if (_fcVehicleId != id) {
        _fcVehicleId = id;
        emit fcVehicleIdChanged();
    }
}

void SimFCCANTestController::setSimVehicleId(int id)
{
    if (_simVehicleId != id) {
        _simVehicleId = id;
        emit simVehicleIdChanged();
    }
}

void SimFCCANTestController::sendFrameToFc(const QString& canId, const QString& hexData)
{
    _sendFrame(_vehicleById(_fcVehicleId), QStringLiteral("fc"), canId, hexData);
}

void SimFCCANTestController::sendFrameToSim(const QString& canId, const QString& hexData)
{
    _sendFrame(_vehicleById(_simVehicleId), QStringLiteral("sim"), canId, hexData);
}

void SimFCCANTestController::sendFcControl(bool flightState, bool packPower, int channelMask)
{
    const QString packData = QStringLiteral("%1 %2")
        .arg(flightState ? QStringLiteral("FF") : QStringLiteral("00"))
        .arg(packPower ? QStringLiteral("FF") : QStringLiteral("00"));

    const QString channelData = QStringLiteral("%1 %2 %3 %4")
        .arg(channelMask & 0x01 ? QStringLiteral("FF") : QStringLiteral("00"))
        .arg(channelMask & 0x02 ? QStringLiteral("FF") : QStringLiteral("00"))
        .arg(channelMask & 0x04 ? QStringLiteral("FF") : QStringLiteral("00"))
        .arg(channelMask & 0x08 ? QStringLiteral("FF") : QStringLiteral("00"));

    sendFrameToFc(QStringLiteral("0x0401F456"), packData);
    sendFrameToFc(QStringLiteral("0x0402F456"), channelData);
}

void SimFCCANTestController::_sendFrame(Vehicle* vehicle, const QString& role, const QString& canId, const QString& hexData)
{
    if (!vehicle) {
        emit errorText(QStringLiteral("No %1 vehicle selected").arg(role));
        return;
    }

    QString normalizedCanId = canId.trimmed();
    QString normalizedHex = hexData.trimmed();
    normalizedHex.replace(QLatin1Char(','), QLatin1Char(' '));

    if (normalizedCanId.isEmpty() || normalizedHex.isEmpty()) {
        emit errorText(QStringLiteral("CAN ID and HEX data are required"));
        return;
    }

    const QString command = QStringLiteral("hybrid_bms_can send %1 %2").arg(normalizedCanId, normalizedHex);
    if (_sendShellCommand(vehicle, command)) {
        emit commandSent(role, normalizedCanId, normalizedHex.simplified().toUpper());
        emit frameReceived(role, QStringLiteral("TX"), normalizedCanId, normalizedHex.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts).size(), normalizedHex.simplified().toUpper(), command);
    }
}

bool SimFCCANTestController::_sendShellCommand(Vehicle* vehicle, const QString& command)
{
    if (!vehicle) {
        return false;
    }

    auto primaryLink = vehicle->vehicleLinkManager()->primaryLink().lock();
    if (!primaryLink) {
        emit errorText(QStringLiteral("No primary link for vehicle %1").arg(vehicle->id()));
        return false;
    }

    QByteArray output(command.toUtf8());
    output.append('\n');

    while (!output.isEmpty()) {
        QByteArray chunk = output.left(MAVLINK_MSG_SERIAL_CONTROL_FIELD_DATA_LEN);
        const int dataSize = chunk.size();
        (void) chunk.append(MAVLINK_MSG_SERIAL_CONTROL_FIELD_DATA_LEN - dataSize, '\0');

        mavlink_message_t msg{};
        const uint8_t flags = SERIAL_CONTROL_FLAG_EXCLUSIVE | SERIAL_CONTROL_FLAG_RESPOND | SERIAL_CONTROL_FLAG_MULTI;
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
            emit errorText(QStringLiteral("Failed to send command to vehicle %1").arg(vehicle->id()));
            return false;
        }

        (void) output.remove(0, dataSize);
    }

    return true;
}

Vehicle* SimFCCANTestController::_vehicleById(int id) const
{
    return (id >= 0 && _manager) ? _manager->getVehicleById(id) : nullptr;
}

QString SimFCCANTestController::_roleForSysId(int sysid) const
{
    if (sysid == _fcVehicleId) {
        return QStringLiteral("fc");
    }
    if (sysid == _simVehicleId) {
        return QStringLiteral("sim");
    }
    return QStringLiteral("unknown");
}

void SimFCCANTestController::_connectVehicle(Vehicle* vehicle)
{
    if (vehicle) {
        _vehicleConnections.append(connect(vehicle, &Vehicle::textMessageReceived, this, &SimFCCANTestController::_handleVehicleTextMessage));
    }
}

void SimFCCANTestController::_vehiclesChanged()
{
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

void SimFCCANTestController::_refreshVehicleIds()
{
    QVariantList ids;
    QmlObjectListModel* vehicles = _manager ? _manager->vehicles() : nullptr;
    if (vehicles) {
        for (int i = 0; i < vehicles->count(); i++) {
            if (Vehicle* vehicle = vehicles->value<Vehicle*>(i)) {
                ids.append(vehicle->id());
            }
        }
    }

    _vehicleIds = ids;
    emit vehicleIdsChanged();

    if (_fcVehicleId < 0 && !ids.isEmpty()) {
        setFcVehicleId(ids.first().toInt());
    }
    if (_simVehicleId < 0) {
        for (const QVariant& id : ids) {
            if (id.toInt() != _fcVehicleId) {
                setSimVehicleId(id.toInt());
                break;
            }
        }
    }
}

bool SimFCCANTestController::_parseFrameText(const QString& text, QString& direction, QString& canId, QString& hexData) const
{
    static const QRegularExpression frameRegex(
        QStringLiteral("\\b(RX|TX)\\b(?:\\[[0-9]+\\])?\\s+(0x)?([0-9A-Fa-f]{3,8})\\s*[: ]\\s*([0-9A-Fa-f, ]{2,191})"));
    const QRegularExpressionMatch match = frameRegex.match(text);
    if (!match.hasMatch()) {
        return false;
    }

    direction = match.captured(1).toUpper();
    canId = QStringLiteral("0x") + match.captured(3).toUpper();
    hexData = match.captured(4).trimmed();
    hexData.replace(QLatin1Char(','), QLatin1Char(' '));
    hexData = hexData.simplified().toUpper();
    return true;
}

void SimFCCANTestController::_handleVehicleTextMessage(int sysid, int componentid, int severity, QString text, QString description)
{
    Q_UNUSED(componentid);
    Q_UNUSED(severity);
    Q_UNUSED(description);

    QString direction;
    QString canId;
    QString hexData;
    if (!_parseFrameText(text, direction, canId, hexData)) {
        return;
    }

    emit frameReceived(_roleForSysId(sysid), direction, canId, hexData.split(QLatin1Char(' '), Qt::SkipEmptyParts).size(), hexData, text);
}
