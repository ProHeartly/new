import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(MobileMouseApp());
}

class MobileMouseApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Mouse',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: ConnectionPage(),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  @override
  _ConnectionPageState createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final TextEditingController _urlController = TextEditingController();
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = 'ws://192.168.1.74:8081'; // Default Python server
  }

  void _connect() async {
    if (_urlController.text.isEmpty) {
      _showSnackBar('Please enter server URL', Colors.red);
      return;
    }

    setState(() => _isConnecting = true);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(_urlController.text));
      
      // Test connection
      await channel.ready;
      
      // Navigate to mouse control page
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => MouseControlPage(
            channel: channel,
            serverUrl: _urlController.text,
          ),
        ),
      );
    } catch (e) {
      setState(() => _isConnecting = false);
      _showSnackBar('Failed to connect: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade400, Colors.blue.shade800],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mouse,
                  size: 80,
                  color: Colors.white,
                ),
                SizedBox(height: 24),
                Text(
                  'Mobile Mouse',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Control your computer mouse wirelessly',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 48),
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: 'Server URL',
                            hintText: 'ws://192.168.1.74:8081',
                            prefixIcon: Icon(Icons.wifi),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isConnecting ? null : _connect,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isConnecting
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text('Connecting...', style: TextStyle(color: Colors.white)),
                                    ],
                                  )
                                : Text('Connect', style: TextStyle(fontSize: 18, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 32),
                Text(
                  'Make sure Python server is running:\npython mouse_server.py',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}

class MouseControlPage extends StatefulWidget {
  final WebSocketChannel channel;
  final String serverUrl;

  MouseControlPage({required this.channel, required this.serverUrl});

  @override
  _MouseControlPageState createState() => _MouseControlPageState();
}

class _MouseControlPageState extends State<MouseControlPage> {
  bool _isConnected = true;
  
  // Movement tracking
  double _accelX = 0.0, _accelY = 0.0, _accelZ = 0.0;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _movementTimer;
  
  // Gravity filter and smoothing
  double _gravityX = 0.0;
  double _gravityY = 0.0;
  double _smoothMovementX = 0.0;
  double _smoothMovementY = 0.0;

  @override
  void initState() {
    super.initState();
    _startSensorListening();
    _startMovementTracking();
    _listenToServer();
  }

  void _startSensorListening() {
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((AccelerometerEvent event) {
      setState(() {
        _accelX = event.x;
        _accelY = event.y;
        _accelZ = event.z;
      });
    });
  }

  void _startMovementTracking() {
    _movementTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (_isConnected) {
        _sendMovementData();
      }
    });
  }

  void _sendMovementData() {
    // Apply gravity filter
    const double gravityFilter = 0.9;
    _gravityX = _gravityX * gravityFilter + _accelX * (1 - gravityFilter);
    _gravityY = _gravityY * gravityFilter + _accelY * (1 - gravityFilter);
    
    double movementX = _accelX - _gravityX;
    double movementY = _accelY - _gravityY;
    
    // Apply smoothing
    const double smoothingFactor = 0.3;
    _smoothMovementX = _smoothMovementX * (1 - smoothingFactor) + movementX * smoothingFactor;
    _smoothMovementY = _smoothMovementY * (1 - smoothingFactor) + movementY * smoothingFactor;
    
    final data = {
      'type': 'motion',
      'movementX': _smoothMovementX,
      'movementY': _smoothMovementY,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    try {
      widget.channel.sink.add(json.encode(data));
    } catch (e) {
      print('Error sending movement data: $e');
    }
  }

  void _listenToServer() {
    widget.channel.stream.listen(
      (data) {
        // Handle server messages
        print('Server message: $data');
      },
      onError: (error) {
        setState(() => _isConnected = false);
        _showSnackBar('Connection error: $error', Colors.red);
      },
      onDone: () {
        setState(() => _isConnected = false);
        _showSnackBar('Connection closed', Colors.orange);
      },
    );
  }

  void _sendClick(String button, String action) {
    final data = {
      'type': 'click',
      'button': button,
      'action': action,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    try {
      widget.channel.sink.add(json.encode(data));
      print('Sent $action $button click');
    } catch (e) {
      print('Error sending click: $e');
    }
  }

  void _sendScroll(String direction) {
    final data = {
      'type': 'scroll',
      'direction': direction,
      'amount': 3,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    try {
      widget.channel.sink.add(json.encode(data));
      print('Sent scroll $direction');
    } catch (e) {
      print('Error sending scroll: $e');
    }
  }

  void _sendTestMessage() {
    final data = {
      'type': 'test',
      'message': 'Test from mobile app',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    try {
      widget.channel.sink.add(json.encode(data));
      _showSnackBar('Test message sent!', Colors.green);
    } catch (e) {
      print('Error sending test: $e');
    }
  }

  void _calibrate() {
    _gravityX = _accelX;
    _gravityY = _accelY;
    _smoothMovementX = 0.0;
    _smoothMovementY = 0.0;
    _showSnackBar('Movement calibrated!', Colors.green);
  }

  void _disconnect() {
    widget.channel.sink.close();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => ConnectionPage()),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mobile Mouse'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _calibrate,
            tooltip: 'Calibrate',
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: _disconnect,
            tooltip: 'Disconnect',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            color: _isConnected ? Colors.green.shade100 : Colors.red.shade100,
            child: Row(
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                SizedBox(width: 8),
                Text(
                  _isConnected ? 'Connected to ${widget.serverUrl}' : 'Disconnected',
                  style: TextStyle(
                    color: _isConnected ? Colors.green.shade800 : Colors.red.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Movement area
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              margin: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app,
                    size: 48,
                    color: Colors.grey.shade600,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Trackpad Area',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Move your phone to control cursor',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Movement: ${_smoothMovementX.toStringAsFixed(3)}, ${_smoothMovementY.toStringAsFixed(3)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Click buttons
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  // Left and Right click
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _sendClick('left', 'click'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.mouse, color: Colors.white),
                              SizedBox(height: 4),
                              Text('Left Click', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _sendClick('right', 'click'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.mouse, color: Colors.white),
                              SizedBox(height: 4),
                              Text('Right Click', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  
                  // Scroll and special buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _sendScroll('up'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.keyboard_arrow_up, color: Colors.white),
                              Text('Scroll Up', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _sendScroll('down'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.keyboard_arrow_down, color: Colors.white),
                              Text('Scroll Down', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  
                  // Test buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _sendClick('left', 'double'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text('Double Click', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _sendTestMessage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text('Test', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _movementTimer?.cancel();
    widget.channel.sink.close();
    super.dispose();
  }
}
     