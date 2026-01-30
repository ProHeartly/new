import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'dart:convert';
import 'dart:async';
import 'dart:math';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3D Mobile Mouse',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MouseControllerPage(),
    );
  }
}

class MouseControllerPage extends StatefulWidget {
  @override
  _MouseControllerPageState createState() => _MouseControllerPageState();
}

class _MouseControllerPageState extends State<MouseControllerPage> {
  WebSocketChannel? _channel;
  String _serverUrl = 'ws://192.168.1.74:8080'; // Your server IP
  bool _isConnected = false;
  
  // Orientation-based tracking (much more stable)
  vm.Quaternion _currentOrientation = vm.Quaternion.identity();
  vm.Quaternion _baseOrientation = vm.Quaternion.identity();
  vm.Quaternion _relativeOrientation = vm.Quaternion.identity();
  
  // Smoothed orientation values
  double _smoothPitch = 0.0;
  double _smoothRoll = 0.0;
  double _smoothYaw = 0.0;
  
  // Raw sensor data for display
  double _gyroX = 0.0, _gyroY = 0.0, _gyroZ = 0.0;
  double _accelX = 0.0, _accelY = 0.0, _accelZ = 0.0;
  double _magX = 0.0, _magY = 0.0, _magZ = 0.0;
  
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  
  Timer? _orientationTimer;
  bool _isCalibrated = false;
  
  // Gravity filter variables for movement detection
  double _gravityX = 0.0;
  double _gravityY = 0.0;
  
  // Smoothing variables for jitter reduction
  double _smoothMovementX = 0.0;
  double _smoothMovementY = 0.0;
  
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = _serverUrl;
    _startSensorListening();
    _startOrientationCalculation();
  }

  void _startSensorListening() {
    // Use normal sensor frequency instead of fastest to avoid permission issues
    _gyroscopeSubscription = gyroscopeEventStream(samplingPeriod: SensorInterval.normalInterval)
        .listen((GyroscopeEvent event) {
      setState(() {
        _gyroX = event.x;
        _gyroY = event.y;
        _gyroZ = event.z;
      });
    });
    
    _accelerometerSubscription = accelerometerEventStream(samplingPeriod: SensorInterval.normalInterval)
        .listen((AccelerometerEvent event) {
      setState(() {
        _accelX = event.x;
        _accelY = event.y;
        _accelZ = event.z;
      });
    });
    
    _magnetometerSubscription = magnetometerEventStream(samplingPeriod: SensorInterval.normalInterval)
        .listen((MagnetometerEvent event) {
      setState(() {
        _magX = event.x;
        _magY = event.y;
        _magZ = event.z;
      });
    });
    
    print('✅ Sensors started with normal sampling rate');
  }
  
  void _startOrientationCalculation() {
    // Calculate movement at 20 FPS (good balance of smoothness and responsiveness)
    _orientationTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      // Send movement data instead of orientation
      if (_isConnected && _channel != null) {
        _sendMovementData();
      }
    });
    print('✅ Movement tracking started at 20 FPS');
  }
  
  void _calculateOrientation() {
    // Simplified orientation calculation - direct from accelerometer
    // Normalize accelerometer
    double accelMagnitude = sqrt(_accelX * _accelX + _accelY * _accelY + _accelZ * _accelZ);
    if (accelMagnitude == 0) return;
    
    double normAccelX = _accelX / accelMagnitude;
    double normAccelY = _accelY / accelMagnitude;
    double normAccelZ = _accelZ / accelMagnitude;
    
    // Calculate pitch and roll directly from accelerometer (much simpler)
    double currentPitch = asin(-normAccelX);
    double currentRoll = atan2(normAccelY, normAccelZ);
    
    // If not calibrated, use current values directly for testing
    if (!_isCalibrated) {
      _smoothPitch = currentPitch * 0.05; // Reduced sensitivity for smoother control
      _smoothRoll = currentRoll * 0.05;   // Reduced sensitivity for smoother control
      _smoothYaw = 0.0;
      return;
    }
    
    // Calculate relative angles from base orientation
    double relativePitch = currentPitch - _basePitch;
    double relativeRoll = currentRoll - _baseRoll;
    
    // Low-pass filter for smoothing
    const double alpha = 0.3; // More responsive
    _smoothPitch = _smoothPitch * (1 - alpha) + relativePitch * alpha;
    _smoothRoll = _smoothRoll * (1 - alpha) + relativeRoll * alpha;
    _smoothYaw = 0.0; // Ignore yaw for now
  }
  
  // Simplified calibration
  double _basePitch = 0.0;
  double _baseRoll = 0.0;
  
  void _calibrateMovement() {
    // Reset the gravity baseline for better movement detection
    _gravityX = _accelX;
    _gravityY = _accelY;
    
    // Reset smoothing values
    _smoothMovementX = 0.0;
    _smoothMovementY = 0.0;
    
    _isCalibrated = true;
    
    print('Movement calibrated - New gravity baseline: X=${_gravityX.toStringAsFixed(2)}, Y=${_gravityY.toStringAsFixed(2)}');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Movement calibrated! Hold phone naturally and move to control cursor.'), backgroundColor: Colors.green),
    );
  }
  
  void _sendMovementData() {
    // Send accelerometer-based movement data (pure phone movement)
    // Filter out gravity to get only movement acceleration
    double movementX = _accelX;
    double movementY = _accelY;
    
    // Apply simple high-pass filter to remove gravity and get movement
    const double gravityFilter = 0.9; // Higher filter for more stable gravity removal
    
    _gravityX = _gravityX * gravityFilter + _accelX * (1 - gravityFilter);
    _gravityY = _gravityY * gravityFilter + _accelY * (1 - gravityFilter);
    
    movementX = _accelX - _gravityX;
    movementY = _accelY - _gravityY;
    
    // Apply smoothing to reduce jitter from shaky hands
    const double smoothingFactor = 0.3; // Smooth out jitter
    _smoothMovementX = _smoothMovementX * (1 - smoothingFactor) + movementX * smoothingFactor;
    _smoothMovementY = _smoothMovementY * (1 - smoothingFactor) + movementY * smoothingFactor;
    
    final data = {
      'type': 'motion',
      'movementX': _smoothMovementX,
      'movementY': _smoothMovementY,
      'rawAccelX': _accelX,
      'rawAccelY': _accelY,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    // Debug: Print every 20 frames (once per second at 20 FPS)
    if (DateTime.now().millisecondsSinceEpoch % 1000 < 50) {
      print('🚀 SENDING: smoothX=${_smoothMovementX.toStringAsFixed(3)}, smoothY=${_smoothMovementY.toStringAsFixed(3)}');
    }
    
    try {
      _channel?.sink.add(json.encode(data));
    } catch (e) {
      print('Error sending data: $e');
    }
  }

  void _connect() {
    try {
      print('🔄 Attempting to connect to: ${_urlController.text}');
      _channel = WebSocketChannel.connect(Uri.parse(_urlController.text));
      
      _channel!.stream.listen(
        (data) {
          print('✅ Received from server: $data');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server says: $data'), backgroundColor: Colors.green),
          );
        },
        onError: (error) {
          print('❌ Connection error: $error');
          setState(() => _isConnected = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection error: $error'), backgroundColor: Colors.red),
          );
        },
        onDone: () {
          print('🔌 Connection closed');
          setState(() => _isConnected = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection closed'), backgroundColor: Colors.orange),
          );
        },
      );
      
      setState(() {
        _isConnected = true;
        _serverUrl = _urlController.text;
      });
      
      print('✅ Connection established, starting immediate test...');
      
      // Send test message IMMEDIATELY
      _sendImmediateTest();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected! Sending test data...'), backgroundColor: Colors.green),
      );
    } catch (e) {
      print('💥 Failed to connect: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e'), backgroundColor: Colors.red),
      );
    }
  }
  
  void _sendImmediateTest() {
    print('🚀 Sending immediate test message...');
    try {
      final testData = {
        'type': 'test',
        'message': 'HELLO FROM MOBILE APP!',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      String jsonData = json.encode(testData);
      print('📤 Sending JSON: $jsonData');
      _channel?.sink.add(jsonData);
      print('✅ Test message sent successfully');
    } catch (e) {
      print('💥 Error sending test: $e');
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    setState(() => _isConnected = false);
  }

  void _testConnection() async {
    try {
      final uri = Uri.parse(_urlController.text.replaceFirst('ws://', 'http://'));
      print('Testing connection to: $uri');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Testing connection to ${uri.host}:${uri.port}...')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid URL: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _sendTestData() {
    print('🧪 Manual test button pressed');
    if (!_isConnected || _channel == null) {
      print('❌ Not connected!');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Not connected to server!'), backgroundColor: Colors.red),
      );
      return;
    }
    
    try {
      final data = {
        'type': 'motion',
        'movementX': 0.5, // Test movement data
        'movementY': 0.3,
        'rawAccelX': 1.0,
        'rawAccelY': 0.5,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      String jsonData = json.encode(data);
      print('📤 Manual test JSON: $jsonData');
      _channel!.sink.add(jsonData);
      print('✅ Manual test sent');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Manual movement test sent!'), backgroundColor: Colors.purple),
      );
    } catch (e) {
      print('💥 Error in manual test: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _orientationTimer?.cancel();
    _channel?.sink.close();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('3D Mobile Mouse')),
      body: SingleChildScrollView( // Make it scrollable
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'ws://192.168.1.74:8080',
              ),
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isConnected ? null : _connect,
                  child: Text('Connect'),
                ),
                ElevatedButton(
                  onPressed: _isConnected ? _disconnect : null,
                  child: Text('Disconnect'),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => _testConnection(),
                  child: Text('Test'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
                ElevatedButton(
                  onPressed: _isConnected ? () => _sendTestData() : null,
                  child: Text('Send Test'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                ),
              ],
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _calibrateMovement(),
              child: Text('Calibrate Movement'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            ),
            SizedBox(height: 16),
            Text(
              'Status: ${_isConnected ? "Connected" : "Disconnected"} | ${_isCalibrated ? "Calibrated" : "Not Calibrated"}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _isConnected && _isCalibrated ? Colors.green : Colors.red,
              ),
            ),
            SizedBox(height: 16),
            // Compact sensor data display
            Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Movement Tracking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Raw Accelerometer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            Text('X: ${_accelX.toStringAsFixed(2)}', style: TextStyle(fontSize: 11)),
                            Text('Y: ${_accelY.toStringAsFixed(2)}', style: TextStyle(fontSize: 11)),
                            Text('Z: ${_accelZ.toStringAsFixed(2)}', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Movement Data', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
                            Text('Move phone to control', style: TextStyle(fontSize: 11, color: Colors.green)),
                            Text('cursor position', style: TextStyle(fontSize: 11, color: Colors.green)),
                            Text('(not rotation)', style: TextStyle(fontSize: 11, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Move phone physically (not rotate) to control cursor like a trackpad!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
            ),
            SizedBox(height: 20), // Extra space at bottom
          ],
        ),
      ),
    );
  }
}