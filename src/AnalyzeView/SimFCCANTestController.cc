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
#include "VehicleLinkManager.h"

#include <QByteArray>
#include <QRegularExpression>
#include <QStringList>
#include <QTimer>
#include <QtGlobal>

namespace {
constexpr qint64 kMinSendIntervalMs = 1000;
}

SimFCCANTestController::SimFCCANTestController(QObject* parent)
    : QObject(parent)
{
    _mavlink = MAVLinkProtocol::instance();
    _manager = MultiVehicleManager::instance();

    (void) connect(_manager, &MultiVehicleManager::activeVehicleChanged, this, &SimFCCANTestController::_setActiveVehicle);

    _lastSendTimer.invalidate();
    _setActiveVehicle(_manager ? _manager->activeVehicle() : nullptr);
}

SimFCCANTestController::~SimFCCANTestController()
{
}

int SimFCCANTestController::activeVehicleId() const
{
    return _vehicle ? _vehicle->id() : -1;
}

void SimFCCANTestController::setVehicleRole(const QString& role)
{
    const QString normalizedRole = (role == QStringLiteral("sim")) ? QStringLiteral("sim") : QStringLiteral("fc");
    if (_vehicleRole != normalizedRole) {
        _vehicleRole = normalizedRole;
        emit vehicleRoleChanged();
    }
}

void SimFCCANTestController::sendFrame(const QString& canId, const QString& hexData)
{
    (void) _sendFrame(canId, hexData, true);
}

void SimFCCANTestController::sendFrameToFc(const QString& canId, const QString& hexData)
{
    setVehicleRole(QStringLiteral("fc"));
    sendFrame(canId, hexData);
}

void SimFCCANTestController::sendFrameToSim(const QString& canId, const QString& hexData)
{
    setVehicleRole(QStringLiteral("sim"));
    sendFrame(canId, hexData);
}

void SimFCCANTestController::sendFcControl(bool flightState, bool packPower, int channelMask)
{
    setVehicleRole(QStringLiteral("fc"));
    const QString command = QStringLiteral("hybrid_bms_can control %1 %2 0x%3")
        .arg(flightState ? 1 : 0)
        .arg(packPower ? 1 : 0)
        .arg(channelMask & 0x0f, 0, 16);

    if (!_validateSendAllowed(1)) {
        return;
    }

    if (_sendShellCommand(command)) {
        emit commandSent(_vehicleRole, QStringLiteral("module"), command);
    }
}

void SimFCCANTestController::startModule(const QString& device, int simPeriodMs)
{
    const QString normalizedDevice = device.trimmed().isEmpty() ? QStringLiteral("can0") : device.trimmed();
    const int normalizedPeriod = qBound(20, simPeriodMs, 5000);
    const QString command = (_vehicleRole == QStringLiteral("sim")) ?
        QStringLiteral("hybrid_bms_can start -m %1 -d %2 -p %3").arg(_vehicleRole, normalizedDevice).arg(normalizedPeriod) :
        QStringLiteral("hybrid_bms_can start -m %1 -d %2").arg(_vehicleRole, normalizedDevice);

    if (!_validateSendAllowed(1)) {
        return;
    }

    if (_sendShellCommand(command)) {
        emit commandSent(_vehicleRole, QStringLiteral("module"), command);
    }
}

void SimFCCANTestController::stopModule()
{
    if (!_validateSendAllowed(1)) {
        return;
    }

    const QString command = QStringLiteral("hybrid_bms_can stop");

    if (_sendShellCommand(command)) {
        emit commandSent(_vehicleRole, QStringLiteral("module"), command);
    }
}

bool SimFCCANTestController::_sendFrame(const QString& canId, const QString& hexData, bool enforceRateLimit)
{
    if (enforceRateLimit && !_validateSendAllowed(1)) {
        return false;
    }

    QString normalizedCanId = canId.trimmed();
    QString normalizedHex = hexData.trimmed();
    normalizedHex.replace(QLatin1Char(','), QLatin1Char(' '));

    if (normalizedCanId.isEmpty() || normalizedHex.isEmpty()) {
        emit errorText(QStringLiteral("CAN ID and HEX data are required"));
        return false;
    }

    const QString command = QStringLiteral("hybrid_bms_can send %1 %2").arg(normalizedCanId, normalizedHex);
    if (_sendShellCommand(command)) {
        emit commandSent(_vehicleRole, normalizedCanId, normalizedHex.simplified().toUpper());
        return true;
    }

    return false;
}

bool SimFCCANTestController::_validateSendAllowed(int commandCount)
{
    if (!_vehicle) {
        emit errorText(QStringLiteral("No active Vehicle connected"));
        return false;
    }

    if (_lastSendTimer.isValid() && _lastSendTimer.elapsed() < kMinSendIntervalMs) {
        emit errorText(QStringLiteral("Send too fast; wait %1 ms before sending again").arg(kMinSendIntervalMs - _lastSendTimer.elapsed()));
        return false;
    }

    if (commandCount <= 0) {
        emit errorText(QStringLiteral("No command to send"));
        return false;
    }

    return true;
}

bool SimFCCANTestController::_sendShellCommand(const QString& command)
{
    return _sendShellCommands(QStringList{command});
}

bool SimFCCANTestController::_sendShellCommands(const QStringList& commands)
{
    if (!_vehicle) {
        emit errorText(QStringLiteral("No active Vehicle connected"));
        return false;
    }

    QByteArray output;
    for (const QString& command : commands) {
        if (command.trimmed().isEmpty()) {
            continue;
        }
        output.append(command.toUtf8());
        output.append('\n');
    }

    if (output.isEmpty()) {
        emit errorText(QStringLiteral("No command to send"));
        return false;
    }

    if (output.size() > MAVLINK_MSG_SERIAL_CONTROL_FIELD_DATA_LEN) {
        emit errorText(QStringLiteral("Command too long for MAVLink shell; use a shorter CAN frame first"));
        return false;
    }

    if (!_sendSerialControl(output, false)) {
        return false;
    }

    QTimer::singleShot(250, this, [this]() {
        (void) _sendSerialControl(QByteArray(), true);
    });

    _lastSendTimer.restart();
    emit errorText(QString());
    return true;
}

bool SimFCCANTestController::_sendSerialControl(const QByteArray& data, bool close)
{
    if (!_vehicle) {
        emit errorText(QStringLiteral("No active Vehicle connected"));
        return false;
    }

    auto primaryLink = _vehicle->vehicleLinkManager()->primaryLink().lock();
    if (!primaryLink) {
        emit errorText(QStringLiteral("No primary link for vehicle %1").arg(_vehicle->id()));
        return false;
    }

    if (data.size() > MAVLINK_MSG_SERIAL_CONTROL_FIELD_DATA_LEN) {
        emit errorText(QStringLiteral("Command too long for MAVLink shell"));
        return false;
    }

    QByteArray chunk = data;
    const int dataSize = chunk.size();
    (void) chunk.append(MAVLINK_MSG_SERIAL_CONTROL_FIELD_DATA_LEN - dataSize, '\0');

    mavlink_message_t msg{};
    const uint8_t flags = close ? 0 : SERIAL_CONTROL_FLAG_EXCLUSIVE | SERIAL_CONTROL_FLAG_RESPOND | SERIAL_CONTROL_FLAG_MULTI;
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
        emit errorText(QStringLiteral("Failed to send command to vehicle %1").arg(_vehicle->id()));
        return false;
    }

    return true;
}

void SimFCCANTestController::_setActiveVehicle(Vehicle* vehicle)
{
    if (_vehicle) {
        (void) disconnect(_vehicle, &Vehicle::textMessageReceived, this, &SimFCCANTestController::_handleVehicleTextMessage);
    }

    _vehicle = vehicle;

    if (_vehicle) {
        (void) connect(_vehicle, &Vehicle::textMessageReceived, this, &SimFCCANTestController::_handleVehicleTextMessage);
    }

    emit activeVehicleChanged();
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
    Q_UNUSED(sysid);
    Q_UNUSED(componentid);
    Q_UNUSED(severity);
    Q_UNUSED(description);

    QString direction;
    QString canId;
    QString hexData;
    if (!_parseFrameText(text, direction, canId, hexData)) {
        return;
    }

    emit frameReceived(_vehicleRole, direction, canId, hexData.split(QLatin1Char(' '), Qt::SkipEmptyParts).size(), hexData, text);
}
