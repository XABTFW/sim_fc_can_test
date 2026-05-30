/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#pragma once

#include <QObject>
#include <QList>
#include <QString>
#include <QVariantList>

#include "MAVLinkProtocol.h"
#include "Vehicle.h"

class MultiVehicleManager;

/// Controller for the "visual_mavlink_test" analyze page.
///
/// It orchestrates a MAVLink round-trip test between the ground station, the
/// simulation vehicle and the real flight controller. The actual transport
/// reuses the PX4 nsh shell (MAVLink SERIAL_CONTROL) to invoke the PX4
/// "visual_mavlink_test" module, and listens for the STATUSTEXT replies the
/// module emits ("VMT:<inc|dec>:<value>").
///
/// Forward test  (地面站 -> 仿真 -> 飞控):
///   1. GCS sends a number to the simulation vehicle (inc).
///   2. Simulation returns number+1, GCS forwards it to the real FC (inc).
///   3. Real FC returns number+1 again, shown in the FC window.
///
/// Reverse test  (地面站 -> 飞控 -> 仿真):
///   1. GCS sends a number to the real FC (dec).
///   2. Real FC returns number-1, GCS forwards it to the simulation (dec).
///   3. Simulation returns number-1 again, shown in the simulation window.
class VisualMavlinkTestController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList vehicleIds   READ vehicleIds   NOTIFY vehicleIdsChanged)
    Q_PROPERTY(int          simVehicleId READ simVehicleId WRITE setSimVehicleId NOTIFY simVehicleIdChanged)
    Q_PROPERTY(int          fcVehicleId  READ fcVehicleId  WRITE setFcVehicleId  NOTIFY fcVehicleIdChanged)

public:
    explicit VisualMavlinkTestController(QObject* parent = nullptr);
    ~VisualMavlinkTestController() override;

    QVariantList vehicleIds() const { return _vehicleIds; }
    int simVehicleId() const { return _simVehicleId; }
    int fcVehicleId() const { return _fcVehicleId; }

    void setSimVehicleId(int id);
    void setFcVehicleId(int id);

    /// Start the forward test: GCS -> simulation (+1) -> real FC (+1).
    Q_INVOKABLE void startForward(int value);

    /// Start the reverse test: GCS -> real FC (-1) -> simulation (-1).
    Q_INVOKABLE void startReverse(int value);

signals:
    void vehicleIdsChanged();
    void simVehicleIdChanged();
    void fcVehicleIdChanged();

    /// A message describing what the simulation vehicle reported.
    void simDataReceived(const QString& data);
    /// A message describing what the real flight controller reported.
    void fcDataReceived(const QString& data);
    /// A message describing data the ground station sent out.
    void dataSent(const QString& data);

private slots:
    void _vehiclesChanged();
    void _handleVehicleTextMessage(int sysid, int componentid, int severity, QString text, QString description);

private:
    enum class Direction {
        None,
        Forward, // inc
        Reverse, // dec
    };

    bool _sendShellCommand(Vehicle* vehicle, const QString& command);
    Vehicle* _vehicleById(int id) const;
    void _connectVehicle(Vehicle* vehicle);
    void _refreshVehicleIds();
    bool _parseValue(const QString& text, const QString& tag, long& valueOut) const;

    MAVLinkProtocol* _mavlink{nullptr};
    MultiVehicleManager* _manager{nullptr};

    QVariantList _vehicleIds;
    int _simVehicleId{-1};
    int _fcVehicleId{-1};

    Direction _direction{Direction::None};

    QList<QMetaObject::Connection> _vehicleConnections;
};
