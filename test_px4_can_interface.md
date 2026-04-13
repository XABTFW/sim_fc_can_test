# PX4 CAN Test 界面集成说明

## 已完成的工作

1. **创建QML界面** (`src/AnalyzeView/PX4CANTestPage.qml`)
   - 左右两列布局，分别显示发送和接收的数据
   - 发送列包含输入框和发送按钮
   - 接收列自动显示接收到的数据
   - 两列都有清空按钮

2. **创建图标** (`src/AnalyzeView/PX4CANTestIcon.svg`)
   - CAN总线风格的SVG图标

3. **创建C++控制器**
   - `src/AnalyzeView/PX4CANTestController.h`
   - `src/AnalyzeView/PX4CANTestController.cc`
   - 提供 `sendCANData()` 方法
   - 提供 `canDataReceived` 和 `canDataSent` 信号

4. **注册到系统**
   - 在 `qgroundcontrol.qrc` 中添加QML文件
   - 在 `qgcimages.qrc` 中添加图标文件
   - 在 `src/API/QGCCorePlugin.cc` 中注册页面（在Vibration后面）
   - 在 `src/QGCApplication.cc` 中注册控制器类型
   - 在 `src/AnalyzeView/CMakeLists.txt` 中添加源文件

## 编译和测试

```bash
cd Qgroundcontrol
mkdir -p build && cd build
cmake ..
make -j$(nproc)
```

## 下一步工作

1. **实现实际的CAN通信逻辑**
   - 在 `PX4CANTestController::sendCANData()` 中实现与PX4的通信
   - 可能需要通过MAVLink发送自定义消息
   - 添加接收数据的处理逻辑

2. **与PX4端集成**
   - 确保PX4端的 `can_test_link` 模块能够接收来自QGC的数据
   - 实现双向通信协议

3. **增强界面功能**
   - 添加数据格式化选项（十六进制/文本）
   - 添加时间戳显示
   - 添加数据统计（发送/接收计数）
   - 添加连接状态指示

## 界面位置

启动QGroundControl后：
1. 点击顶部工具栏的 "Analyze Tools"
2. 在左侧菜单中找到 "PX4 CAN Test"（在 "Vibration" 下面）
3. 点击即可打开界面
