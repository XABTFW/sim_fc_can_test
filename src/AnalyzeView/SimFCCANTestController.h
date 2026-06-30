/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QString>
#include <QStringList>

#include "MAVLinkProtocol.h"
#include "Vehicle.h"

class MultiVehicleManager;

class SimFCCANTestController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool activeVehicleAvailable READ activeVehicleAvailable NOTIFY activeVehicleChanged)
    Q_PROPERTY(int activeVehicleId READ activeVehicleId NOTIFY activeVehicleChanged)
    Q_PROPERTY(QString vehicleRole READ vehicleRole WRITE setVehicleRole NOTIFY vehicleRoleChanged)

public:
    explicit SimFCCANTestController(QObject* parent = nullptr);
    ~SimFCCANTestController() override;

    bool activeVehicleAvailable() const { return _vehicle != nullptr; }
    int activeVehicleId() const;
    QString vehicleRole() const { return _vehicleRole; }

    void setVehicleRole(const QString& role);

    Q_INVOKABLE void sendFrame(const QString& canId, const QString& hexData);
    Q_INVOKABLE void sendFrameToFc(const QString& canId, const QString& hexData);
    Q_INVOKABLE void sendFrameToSim(const QString& canId, const QString& hexData);
    Q_INVOKABLE void sendFcControl(bool flightState, bool packPower, int channelMask);

signals:
    void activeVehicleChanged();
    void vehicleRoleChanged();
    void frameReceived(const QString& role, const QString& direction, const QString& canId, int len, const QString& hexData, const QString& rawText);
    void commandSent(const QString& role, const QString& canId, const QString& hexData);
    void errorText(const QString& text);

private slots:
    void _setActiveVehicle(Vehicle* vehicle);
    void _handleVehicleTextMessage(int sysid, int componentid, int severity, QString text, QString description);

private:
    bool _sendShellCommand(const QString& command);
    bool _sendShellCommands(const QStringList& commands);
    bool _validateSendAllowed(int commandCount);
    bool _parseFrameText(const QString& text, QString& direction, QString& canId, QString& hexData) const;
    bool _sendFrame(const QString& canId, const QString& hexData, bool enforceRateLimit);

    MAVLinkProtocol* _mavlink{nullptr};
    MultiVehicleManager* _manager{nullptr};
    Vehicle* _vehicle{nullptr};
    QString _vehicleRole{QStringLiteral("fc")};
    QElapsedTimer _lastSendTimer;
};
