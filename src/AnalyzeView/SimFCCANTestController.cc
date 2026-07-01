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
#include <QtGlobal>

#include <cstdint>

namespace {
constexpr qint64 kMinSendIntervalMs = 1000;
constexpr uint16_t kHybridBmsTunnelPayloadType = 32001;
constexpr uint8_t kHybridBmsTunnelVersion = 1;
constexpr uint32_t kPackControlCommandId = 0x0401f456;
constexpr uint32_t kOutputControlCommandId = 0x0402f456;
constexpr uint32_t kPackControlResponseId = 0x040156f4;
constexpr uint32_t kOutputControlResponseId = 0x040256f4;
constexpr uint32_t kMbmsStatusId = 0x041256f4;
constexpr uint32_t kMbmsDataId = 0x041356f4;
constexpr uint32_t kLvBatteryDataId = 0x042056f4;
constexpr uint32_t kDcdcDataId = 0x043056f4;
constexpr uint32_t kSimNumberTestId = 0x044056f4;

enum class HybridBmsTunnelOpcode : uint8_t {
    Start = 1,
    Stop = 2,
    Control = 3,
    SendFrame = 4,
};

QByteArray tunnelHeader(HybridBmsTunnelOpcode opcode)
{
    QByteArray payload;
    payload.append('H');
    payload.append('B');
    payload.append('M');
    payload.append('S');
    payload.append(static_cast<char>(kHybridBmsTunnelVersion));
    payload.append(static_cast<char>(opcode));
    return payload;
}

void appendU16(QByteArray& payload, uint16_t value)
{
    payload.append(static_cast<char>(value & 0xff));
    payload.append(static_cast<char>((value >> 8) & 0xff));
}

void appendU32(QByteArray& payload, uint32_t value)
{
    payload.append(static_cast<char>(value & 0xff));
    payload.append(static_cast<char>((value >> 8) & 0xff));
    payload.append(static_cast<char>((value >> 16) & 0xff));
    payload.append(static_cast<char>((value >> 24) & 0xff));
}

bool isFcToSimFrame(uint32_t canId)
{
    return canId == kPackControlCommandId || canId == kOutputControlCommandId;
}

bool isSimToFcFrame(uint32_t canId)
{
    switch (canId) {
    case kPackControlResponseId:
    case kOutputControlResponseId:
    case kMbmsStatusId:
    case kMbmsDataId:
    case kLvBatteryDataId:
    case kDcdcDataId:
    case kSimNumberTestId:
        return true;
    default:
        return false;
    }
}
}

SimFCCANTestController::SimFCCANTestController(QObject* parent)
    : QObject(parent)
{
    _mavlink = MAVLinkProtocol::instance();
    _manager = MultiVehicleManager::instance();

    (void) connect(_manager, &MultiVehicleManager::activeVehicleChanged, this, &SimFCCANTestController::_setActiveVehicle);
    (void) connect(_manager, &MultiVehicleManager::vehicleAdded, this, &SimFCCANTestController::_vehiclesChanged);
    (void) connect(_manager, &MultiVehicleManager::vehicleRemoved, this, &SimFCCANTestController::_vehiclesChanged);

    _lastSendTimer.invalidate();
    _setActiveVehicle(_manager ? _manager->activeVehicle() : nullptr);
    _vehiclesChanged();
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

    if (!_validateSendAllowed(_vehicleRole, 1)) {
        return;
    }

    QByteArray payload = tunnelHeader(HybridBmsTunnelOpcode::Control);
    payload.append(static_cast<char>(flightState ? 1 : 0));
    payload.append(static_cast<char>(packPower ? 1 : 0));
    payload.append(static_cast<char>(channelMask & 0x0f));

    const QString command = QStringLiteral("hybrid_bms_can control %1 %2 0x%3")
        .arg(flightState ? 1 : 0)
        .arg(packPower ? 1 : 0)
        .arg(channelMask & 0x0f, 0, 16);

    Vehicle* targetVehicle = _targetVehicleForRole(_vehicleRole);
    if (_sendTunnelPayload(targetVehicle, payload)) {
        emit commandSent(_vehicleRole, QStringLiteral("module"), command);
    }
}

void SimFCCANTestController::startModule(const QString& device, int simPeriodMs)
{
    const QString normalizedDevice = device.trimmed().isEmpty() ? QStringLiteral("can0") : device.trimmed();
    const int normalizedPeriod = qBound(20, simPeriodMs, 5000);
    const uint8_t deviceIndex = normalizedDevice.compare(QStringLiteral("can1"), Qt::CaseInsensitive) == 0 ? 1 : 0;
    const QString command = (_vehicleRole == QStringLiteral("sim")) ?
        QStringLiteral("hybrid_bms_can start -m %1 -d %2 -p %3").arg(_vehicleRole, normalizedDevice).arg(normalizedPeriod) :
        QStringLiteral("hybrid_bms_can start -m %1 -d %2").arg(_vehicleRole, normalizedDevice);

    if (_vehicleRole == QStringLiteral("sim")) {
        _simVehicle = _vehicle;
    } else {
        _fcVehicle = _vehicle;
    }

    if (!_validateSendAllowed(_vehicleRole, 1)) {
        return;
    }

    QByteArray payload = tunnelHeader(HybridBmsTunnelOpcode::Start);
    payload.append(static_cast<char>(_vehicleRole == QStringLiteral("sim") ? 2 : 1));
    payload.append(static_cast<char>(deviceIndex));
    appendU16(payload, static_cast<uint16_t>(normalizedPeriod));

    Vehicle* targetVehicle = _targetVehicleForRole(_vehicleRole);
    if (_sendTunnelPayload(targetVehicle, payload)) {
        emit commandSent(_vehicleRole, QStringLiteral("module"), command);
    }
}

void SimFCCANTestController::stopModule()
{
    if (!_validateSendAllowed(_vehicleRole, 1)) {
        return;
    }

    const QString command = QStringLiteral("hybrid_bms_can stop");

    QByteArray payload = tunnelHeader(HybridBmsTunnelOpcode::Stop);

    Vehicle* targetVehicle = _targetVehicleForRole(_vehicleRole);
    if (_sendTunnelPayload(targetVehicle, payload)) {
        emit commandSent(_vehicleRole, QStringLiteral("module"), command);
    }
}

bool SimFCCANTestController::_sendFrame(const QString& canId, const QString& hexData, bool enforceRateLimit)
{
    if (enforceRateLimit && !_validateSendAllowed(_vehicleRole, 1)) {
        return false;
    }

    QString normalizedCanId = canId.trimmed();
    QString normalizedHex = hexData.trimmed();

    QVector<uint8_t> bytes;
    if (normalizedCanId.isEmpty() || normalizedHex.isEmpty() || !_parseHexData(normalizedHex, bytes)) {
        emit errorText(QStringLiteral("CAN ID and HEX data are required"));
        return false;
    }

    bool ok = false;
    const uint32_t parsedCanId = normalizedCanId.toUInt(&ok, 0);
    if (!ok || parsedCanId > 0x1fffffff || bytes.size() > 64) {
        emit errorText(QStringLiteral("Invalid CAN ID or CAN FD data length"));
        return false;
    }

    QByteArray payload = tunnelHeader(HybridBmsTunnelOpcode::SendFrame);
    appendU32(payload, parsedCanId);
    payload.append(static_cast<char>(bytes.size()));

    for (uint8_t byte : bytes) {
        payload.append(static_cast<char>(byte));
    }

    Vehicle* targetVehicle = _targetVehicleForRole(_vehicleRole);
    if (_sendTunnelPayload(targetVehicle, payload)) {
        emit commandSent(_vehicleRole, normalizedCanId, normalizedHex.simplified().toUpper());
        return true;
    }

    return false;
}

bool SimFCCANTestController::_validateSendAllowed(const QString& role, int commandCount)
{
    if (!_targetVehicleForRole(role)) {
        emit errorText(QStringLiteral("No %1 Vehicle bound. Select that vehicle, open the %2 tab, then click Start current role.")
            .arg(role.toUpper(), role.toUpper()));
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

bool SimFCCANTestController::_sendTunnelPayload(Vehicle* vehicle, const QByteArray& payload)
{
    if (!vehicle) {
        emit errorText(QStringLiteral("No target Vehicle connected"));
        return false;
    }

    if (payload.isEmpty() || payload.size() > MAVLINK_MSG_TUNNEL_FIELD_PAYLOAD_LEN) {
        emit errorText(QStringLiteral("Invalid hybrid BMS MAVLink tunnel payload"));
        return false;
    }

    auto primaryLink = vehicle->vehicleLinkManager()->primaryLink().lock();
    if (!primaryLink) {
        emit errorText(QStringLiteral("No primary link for vehicle %1").arg(vehicle->id()));
        return false;
    }

    QByteArray tunnelPayload = payload;
    const int payloadSize = tunnelPayload.size();
    (void) tunnelPayload.append(MAVLINK_MSG_TUNNEL_FIELD_PAYLOAD_LEN - payloadSize, '\0');

    mavlink_message_t msg{};
    (void) mavlink_msg_tunnel_pack_chan(
        _mavlink->getSystemId(),
        _mavlink->getComponentId(),
        primaryLink->mavlinkChannel(),
        &msg,
        vehicle->id(),
        vehicle->defaultComponentId(),
        kHybridBmsTunnelPayloadType,
        payloadSize,
        reinterpret_cast<uint8_t*>(tunnelPayload.data()));

    if (!vehicle->sendMessageOnLinkThreadSafe(primaryLink.get(), msg)) {
        emit errorText(QStringLiteral("Failed to send command to vehicle %1").arg(vehicle->id()));
        return false;
    }

    _lastSendTimer.restart();
    emit errorText(QString());
    return true;
}

bool SimFCCANTestController::_parseHexData(const QString& hexData, QVector<uint8_t>& bytesOut) const
{
    QString clean = hexData;
    clean.replace(QStringLiteral("0x"), QStringLiteral(" "), Qt::CaseInsensitive);
    clean.replace(QLatin1Char(','), QLatin1Char(' '));
    clean.replace(QRegularExpression(QStringLiteral("[^0-9A-Fa-f]")), QStringLiteral(" "));

    const QStringList parts = clean.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    bytesOut.clear();

    for (const QString& part : parts) {
        if (part.size() > 2) {
            if (part.size() % 2 != 0) {
                return false;
            }

            for (int i = 0; i < part.size(); i += 2) {
                bool ok = false;
                const uint value = part.mid(i, 2).toUInt(&ok, 16);
                if (!ok || value > 0xff) {
                    return false;
                }
                bytesOut.append(static_cast<uint8_t>(value));
            }

        } else {
            bool ok = false;
            const uint value = part.toUInt(&ok, 16);
            if (!ok || value > 0xff) {
                return false;
            }
            bytesOut.append(static_cast<uint8_t>(value));
        }
    }

    return !bytesOut.isEmpty() && bytesOut.size() <= 64;
}

void SimFCCANTestController::_setActiveVehicle(Vehicle* vehicle)
{
    _vehicle = vehicle;
    emit activeVehicleChanged();
}

void SimFCCANTestController::_connectVehicle(Vehicle* vehicle)
{
    if (!vehicle) {
        return;
    }

    _vehicleConnections.append(
        connect(vehicle, &Vehicle::textMessageReceived, this, &SimFCCANTestController::_handleVehicleTextMessage));
}

void SimFCCANTestController::_vehiclesChanged()
{
    for (const QMetaObject::Connection& connection : _vehicleConnections) {
        (void) disconnect(connection);
    }

    _vehicleConnections.clear();

    QmlObjectListModel* vehicles = _manager ? _manager->vehicles() : nullptr;

    if (!vehicles) {
        _fcVehicle = nullptr;
        _simVehicle = nullptr;
        return;
    }

    bool fcStillConnected = false;
    bool simStillConnected = false;

    for (int i = 0; i < vehicles->count(); i++) {
        Vehicle* vehicle = vehicles->value<Vehicle*>(i);
        _connectVehicle(vehicle);
        fcStillConnected = fcStillConnected || vehicle == _fcVehicle;
        simStillConnected = simStillConnected || vehicle == _simVehicle;
    }

    if (!fcStillConnected) {
        _fcVehicle = nullptr;
    }

    if (!simStillConnected) {
        _simVehicle = nullptr;
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

    emit frameReceived(_roleForFrame(sysid, direction, canId), direction, canId, hexData.split(QLatin1Char(' '), Qt::SkipEmptyParts).size(), hexData, text);
}

Vehicle* SimFCCANTestController::_targetVehicleForRole(const QString& role) const
{
    Vehicle* roleVehicle = (role == QStringLiteral("sim")) ? _simVehicle : _fcVehicle;
    return roleVehicle ? roleVehicle : _vehicle;
}

QString SimFCCANTestController::_roleForFrame(int sysid, const QString& direction, const QString& canId) const
{
    bool ok = false;
    const uint32_t parsedCanId = canId.toUInt(&ok, 0);

    if (ok) {
        if (direction == QStringLiteral("RX")) {
            if (isSimToFcFrame(parsedCanId)) {
                return QStringLiteral("fc");
            }

            if (isFcToSimFrame(parsedCanId)) {
                return QStringLiteral("sim");
            }

        } else if (direction == QStringLiteral("TX")) {
            if (isSimToFcFrame(parsedCanId)) {
                return QStringLiteral("sim");
            }

            if (isFcToSimFrame(parsedCanId)) {
                return QStringLiteral("fc");
            }
        }
    }

    if (_simVehicle && sysid == _simVehicle->id()) {
        return QStringLiteral("sim");
    }

    if (_fcVehicle && sysid == _fcVehicle->id()) {
        return QStringLiteral("fc");
    }

    return _vehicleRole;
}
