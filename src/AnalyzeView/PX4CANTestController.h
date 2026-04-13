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
#include <QString>

#include "MAVLinkProtocol.h"
#include "Vehicle.h"

class PX4CANTestController : public QObject
{
    Q_OBJECT

public:
    explicit PX4CANTestController(QObject* parent = nullptr);
    ~PX4CANTestController() override;

    Q_INVOKABLE void sendCANData(const QString& data);
    Q_INVOKABLE void startReceive(const QString& device = QStringLiteral("can0"));
    Q_INVOKABLE void stopReceive();

signals:
    void canDataReceived(const QString& data);
    void canDataSent(const QString& data);
    void receiveRunningChanged(bool running);

private slots:
    void _setActiveVehicle(Vehicle* vehicle);
    void _handleVehicleTextMessage(int sysid, int componentid, int severity, QString text, QString description);

private:
    enum class Role {
        Idle,
        Receive,
    };

    bool _sendShellCommand(const QString& command);
    void _setRole(Role role);

    MAVLinkProtocol* _mavlink{nullptr};
    Vehicle* _vehicle{nullptr};
    Role _role{Role::Idle};
};
