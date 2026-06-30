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
#include <QList>
#include <QMetaObject>
#include <QVariantList>

#include "MAVLinkProtocol.h"
#include "Vehicle.h"

class MultiVehicleManager;

class SimFCCANTestController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList vehicleIds READ vehicleIds NOTIFY vehicleIdsChanged)
    Q_PROPERTY(int fcVehicleId READ fcVehicleId WRITE setFcVehicleId NOTIFY fcVehicleIdChanged)
    Q_PROPERTY(int simVehicleId READ simVehicleId WRITE setSimVehicleId NOTIFY simVehicleIdChanged)

public:
    explicit SimFCCANTestController(QObject* parent = nullptr);
    ~SimFCCANTestController() override;

    QVariantList vehicleIds() const { return _vehicleIds; }
    int fcVehicleId() const { return _fcVehicleId; }
    int simVehicleId() const { return _simVehicleId; }

    void setFcVehicleId(int id);
    void setSimVehicleId(int id);

    Q_INVOKABLE void sendFrameToFc(const QString& canId, const QString& hexData);
    Q_INVOKABLE void sendFrameToSim(const QString& canId, const QString& hexData);
    Q_INVOKABLE void sendFcControl(bool flightState, bool packPower, int channelMask);

signals:
    void vehicleIdsChanged();
    void fcVehicleIdChanged();
    void simVehicleIdChanged();
    void frameReceived(const QString& role, const QString& direction, const QString& canId, int len, const QString& hexData, const QString& rawText);
    void commandSent(const QString& role, const QString& canId, const QString& hexData);
    void errorText(const QString& text);

private slots:
    void _vehiclesChanged();
    void _handleVehicleTextMessage(int sysid, int componentid, int severity, QString text, QString description);

private:
    bool _sendShellCommand(Vehicle* vehicle, const QString& command);
    Vehicle* _vehicleById(int id) const;
    QString _roleForSysId(int sysid) const;
    void _connectVehicle(Vehicle* vehicle);
    void _refreshVehicleIds();
    bool _parseFrameText(const QString& text, QString& direction, QString& canId, QString& hexData) const;
    void _sendFrame(Vehicle* vehicle, const QString& role, const QString& canId, const QString& hexData);

    MAVLinkProtocol* _mavlink{nullptr};
    MultiVehicleManager* _manager{nullptr};
    QVariantList _vehicleIds;
    int _fcVehicleId{-1};
    int _simVehicleId{-1};
    QList<QMetaObject::Connection> _vehicleConnections;
};
