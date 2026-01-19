#ifndef SWARM_SEND_H
#define SWARM_SEND_H

#include "Vehicle.h"
#include "QmlObjectListModel.h"
#include "Fact.h"
#include "FactMetaData.h"
#include <QObject>
#include <QString>
#include <QMetaObject>
#include <QStringListModel>

#include <ParameterManager.h>
#include <FactMetaData.h>
// Fordward decls
class Vehicle;


class Swarm_send : public QObject
{
    Q_OBJECT
public:
    explicit Swarm_send(QObject *parent = nullptr);
    Q_INVOKABLE void caculate_pos(int sysid,float x,float y,float z);
    Q_INVOKABLE void set_main_airplane(int sysid, int grp_id, float x,float y,float z);
    Q_INVOKABLE void store_airplane_group(int sysid, int group_id, bool flag = false, bool set_as_follower = false);
    Q_INVOKABLE void set_absolute_altitude(int sysid, float altitude);  // 设置绝对高度

    // 静态实例，用于全局访问
    static Swarm_send* instance();
    
    // 发射主机航线高度变化信号
    Q_INVOKABLE void emitMainAltitudeChanged(int vehicleId, double altitude);

signals:
    // 主机航线高度变化信号 - 当上传航线时发射
    void mainAltitudeChanged(int vehicleId, double altitude);

private:
    static Swarm_send* _instance;
    int main_airplane = 0;
    QMap<int,int> group_id;
    QVector<float> vec_;
};

#endif // SWARM_SEND_H
