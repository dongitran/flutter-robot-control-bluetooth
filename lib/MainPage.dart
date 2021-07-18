import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:sensors/sensors.dart';
import 'package:toggle_switch/toggle_switch.dart';


import './BackgroundCollectedPage.dart';
import './BackgroundCollectingTask.dart';
import './ChatPage.dart';
import './DiscoveryPage.dart';
import './SelectBondedDevicePage.dart';


// import './helpers/LineChart.dart';

class MainPage extends StatefulWidget {
  @override
  _MainPage createState() => new _MainPage();
}

class _MainPage extends State<MainPage> {
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;

  String _address = "...";
  String _name = "...";

  Timer? _discoverableTimeoutTimer;
  int _discoverableTimeoutSecondsLeft = 0;

  BackgroundCollectingTask? _collectingTask;

  bool _autoAcceptPairingRequests = false;
  bool isConnected = false;
  bool isDisconnecting = true;
  bool isSending = false;

  List<double>? _accelerometerValues;
  List<double>? _userAccelerometerValues;
  List<double>? _gyroscopeValues;
  List<StreamSubscription<dynamic>> _streamSubscriptions =
  <StreamSubscription<dynamic>>[];

  int counterReadSensor = 0;
  double velocity = 0;
  double angle = 90;
  int controlCommand = 1;

  @override
  void initState() {
    super.initState();

    // Get current state
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
    });

    Future.doWhile(() async {
      // Wait if adapter not enabled
      if ((await FlutterBluetoothSerial.instance.isEnabled) ?? false) {
        return false;
      }
      await Future.delayed(Duration(milliseconds: 0xDD));
      return true;
    }).then((_) {
      // Update the address field
      FlutterBluetoothSerial.instance.address.then((address) {
        setState(() {
          _address = address!;
        });
      });
    });

    FlutterBluetoothSerial.instance.name.then((name) {
      setState(() {
        _name = name!;
      });
    });

    // Listen for futher state changes
    FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;

        // Discoverable mode is disabled when Bluetooth gets disabled
        _discoverableTimeoutTimer = null;
        _discoverableTimeoutSecondsLeft = 0;
      });
    });

    accelerometerEvents.listen((AccelerometerEvent event) {
      //print((event.y*100).round());
      counterReadSensor++;
      //print(counterReadSensor);
      double sensorValue = (event.y*100);
      if(isConnected){
        _sendMessage(sensorValue.round().toString() + "," + velocity.round().toString() + "," + controlCommand.toString());
      }
      setState(() {
        angle = ((angle*1) + (90 + (sensorValue*90/1000)))/2;
      });
    });
    // [AccelerometerEvent (x: 0.0, y: 9.8, z: 0.0)]
  }

  @override
  void dispose() {
    FlutterBluetoothSerial.instance.setPairingRequestHandler(null);
    _collectingTask?.dispose();
    _discoverableTimeoutTimer?.cancel();

    if (isConnected) {
      isDisconnecting = true;
      connection?.dispose();
      connection = null;
    }

    super.dispose();
  }

  BluetoothConnection? connection;

  void _onDataReceived(Uint8List data) {
    print("Received");
    // Allocate buffer for parsed data
    int backspacesCounter = 0;
    data.forEach((byte) {
      if (byte == 8 || byte == 127) {
        backspacesCounter++;
      }
      if(byte == '\r'){
        isSending = false;
      }
    });
    Uint8List buffer = Uint8List(data.length - backspacesCounter);
    int bufferIndex = buffer.length;

    // Apply backspace control character
    backspacesCounter = 0;
    for (int i = data.length - 1; i >= 0; i--) {
      if (data[i] == 8 || data[i] == 127) {
        backspacesCounter++;
      } else {
        if (backspacesCounter > 0) {
          backspacesCounter--;
        } else {
          buffer[--bufferIndex] = data[i];
        }
      }
    }

    // Create message if there is new line character
    String dataString = String.fromCharCodes(buffer);
    print(dataString);
    int index = buffer.indexOf(13);
    if (~index != 0) {

    } else {

    }
  }
  void _sendMessage(String text) async {
    if(!isSending){
      //print("Send" + text);
      text = text.trim();

      if (text.length > 0) {
        try {
          connection!.output.add(Uint8List.fromList(utf8.encode(text + "\r")));
          await connection!.output.allSent;

        } catch (e) {
          // Ignore error, but notify state
          print("Write error");
        }
      }
    }

  }
  void SetConnection(BluetoothConnection con){
    print("set connection");
    isConnected = true;
    connection = con;
  }

  @override
  Widget build(BuildContext context) {
    double height = MediaQuery.of(context).size.height;
    return Scaffold(
      drawer: NavDrawer(setConnection: SetConnection, onDataReceived: _onDataReceived),
      appBar: AppBar(
        title: const Text('Agv control'),
      ),
      body: Container(
        child: Column(
          children: [
            Container(
              height: height/8,
              child: Slider(
                  value: velocity,
                  onChanged: (val){setState(() {
                    velocity = val;
                  });},
                  min: 0,
                  max: 100
              ),
            ),
            Container(
              height: height*5/8,
              child: Transform.rotate(
                angle: 3.14159 / 180 * angle,
                child: Image(
                  fit: BoxFit.none,
                  image: AssetImage('assets/images/robot.png'),
                ),
              )
            ),
            Container(
              height: height*1/8,
              padding: EdgeInsets.only(top: height/50, bottom: height/50),
              child: ToggleSwitch(
                inactiveBgColor: Colors.deepOrangeAccent,
                initialLabelIndex: controlCommand,
                totalSwitches: 3,
                fontSize: 50,
                labels: ['<', '|', '>'],
                onToggle: (index) {
                  controlCommand = index;
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  void _startChat(BuildContext context, BluetoothDevice server) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return ChatPage(server: server);
        },
      ),
    );
  }

  Future<void> _startBackgroundTask(
    BuildContext context,
    BluetoothDevice server,
  ) async {
    try {
      _collectingTask = await BackgroundCollectingTask.connect(server);
      await _collectingTask!.start();
    } catch (ex) {
      _collectingTask?.cancel();
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Error occured while connecting'),
            content: Text("${ex.toString()}"),
            actions: <Widget>[
              new TextButton(
                child: new Text("Close"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }
}

class NavDrawer extends StatefulWidget {
  NavDrawer({Key? key, required this.setConnection, required this.onDataReceived}) : super(key: key);

  final Function setConnection;
  final void Function(Uint8List)? onDataReceived;

  @override
  _NavDrawerState createState() => _NavDrawerState();
}

class _NavDrawerState extends State<NavDrawer> {

  void connectBle(BluetoothDevice bleDevice){
    BluetoothConnection? connection;
    BluetoothConnection.toAddress(bleDevice.address).then((_connection) {
      print('Connected to the device');
      connection = _connection;

      connection!.input!.listen(widget.onDataReceived).onDone(() {
        print('Disconnecting locally!');
      });
      widget.setConnection(connection);
    }).catchError((error) {
      print('Cannot connect, exception occured');
      print(error);
    });
  }
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            child: Text(
              '',
              style: TextStyle(color: Colors.white, fontSize: 25),
            ),
            decoration: BoxDecoration(
                color: Colors.lightBlueAccent,
                image: DecorationImage(
                    fit: BoxFit.none,
                    image: AssetImage('assets/images/cover.png'))),
          ),
          ListTile(
            leading: Icon(Icons.input),
            title: Text('Home'),
            onTap: () => {
              //_sendMessage("adsdf")

            },
          ),
          ListTile(
            leading: Icon(Icons.settings),
            title: Text('Settings'),
            onTap: () async {
              Navigator.pop(context);
              final BluetoothDevice? selectedDevice =
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) {
                    return SelectBondedDevicePage(checkAvailability: false);
                  },
                ),
              );

              if (selectedDevice != null) {
                print('Connect -> selected ' + selectedDevice.address);
                connectBle(selectedDevice);
              } else {
                print('Connect -> no device selected');
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.border_color),
            title: Text('Info'),
            onTap: () => {Navigator.of(context).pop()},
          ),
        ],
      ),
    );
  }
}