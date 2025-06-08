import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'print_text_page.dart';

class BluetoothScanPage extends StatefulWidget {
  final Uint8List? imageBytes;
  const BluetoothScanPage({super.key, this.imageBytes});

  @override
  State<BluetoothScanPage> createState() => _BluetoothScanPageState();
}

class _BluetoothScanPageState extends State<BluetoothScanPage> {
  bool _isBluetoothOn = false;
  bool _isLoading = true;
  late final Stream<BluetoothAdapterState> _stateStream;
  bool _isConnected = false;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _serialCharacteristic;

  static const String serialServiceUUID =
      "49535343-fe7d-4ae5-8fa9-9fafd205e455";
  static const String serialCharUUID = "49535343-8841-43f4-a8d4-ecbe34729bb3";

  @override
  void initState() {
    super.initState();
    _ensurePermissions().then((_) async {
      _stateStream = FlutterBluePlus.adapterState;
      _listenBluetoothState();

      // Try auto-connect to saved device with up to 3 attempts
      final saved = await _loadDeviceProfile();
      if (saved != null) {
        setState(() {
          _isLoading = true;
        });
        bool connected = false;
        for (int attempt = 1; attempt <= 3; attempt++) {
          setState(() {
            _isLoading = true;
          });
          try {
            debugPrint('Auto-connect attempt $attempt to ${saved['id']}');
            final devices = await FlutterBluePlus.connectedDevices;
            BluetoothDevice device;
            try {
              device = devices.firstWhere(
                (d) => d.remoteId.str == saved['id'],
                orElse: () => BluetoothDevice.fromId(saved['id']),
              );
            } catch (_) {
              device = BluetoothDevice.fromId(saved['id']);
            }
            await Future.delayed(const Duration(seconds: 2));
            await device.connect(timeout: const Duration(seconds: 10));
            List<BluetoothService> services = await device.discoverServices();
            final service = services.firstWhere(
              (s) => s.uuid.str.toLowerCase() == serialServiceUUID,
              orElse: () => throw Exception('Serial service not found'),
            );
            final characteristic = service.characteristics.firstWhere(
              (c) => c.uuid.str.toLowerCase() == serialCharUUID,
              orElse: () => throw Exception('Serial characteristic not found'),
            );
            setState(() {
              _isConnected = true;
              _connectedDevice = device;
              _serialCharacteristic = characteristic;
              _isLoading = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PrintTextPage(
                    serialCharacteristic: _serialCharacteristic!,
                    device: _connectedDevice!,
                    imageBytes: widget.imageBytes,
                  ),
                ),
              );
              setState(() {
                _isConnected = false;
                _connectedDevice = null;
                _serialCharacteristic = null;
              });
            });
            connected = true;
            break; // Success, stop retrying
          } catch (e) {
            debugPrint('Auto-connect attempt $attempt failed: $e');
            setState(() {
              _isLoading = true;
            });
            await Future.delayed(const Duration(seconds: 2));
          }
        }
        setState(() {
          _isLoading = false;
        });
        if (!connected) {
          debugPrint('Failed to auto-connect after 3 attempts.');
          // Continue to show device list for user selection
        } else {
          return; // Connected, skip showing device list
        }
      }

      // Check for already connected devices and go to PrintTextPage if found
      final connectedDevices = await FlutterBluePlus.connectedDevices;
      for (final device in connectedDevices) {
        try {
          List<BluetoothService> services = await device.discoverServices();
          final service = services.firstWhere(
            (s) => s.uuid.str.toLowerCase() == serialServiceUUID,
            orElse: () => throw Exception('Serial service not found'),
          );
          final characteristic = service.characteristics.firstWhere(
            (c) => c.uuid.str.toLowerCase() == serialCharUUID,
            orElse: () => throw Exception('Serial characteristic not found'),
          );
          setState(() {
            _isConnected = true;
            _connectedDevice = device;
            _serialCharacteristic = characteristic;
          });
          // Navigate to PrintTextPage
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PrintTextPage(
                  serialCharacteristic: _serialCharacteristic!,
                  device: _connectedDevice!,
                  imageBytes: widget.imageBytes,
                ),
              ),
            );
            setState(() {
              _isConnected = false;
              _connectedDevice = null;
              _serialCharacteristic = null;
            });
          });
          break; // Only handle the first connected printer
        } catch (_) {
          // Not a serial printer, continue checking others
        }
      }
    });
  }

  Future<void> _ensurePermissions() async {
    await Permission.location.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
  }

  void _listenBluetoothState() {
    _stateStream.listen((state) async {
      final isOn = state == BluetoothAdapterState.on;
      setState(() {
        _isBluetoothOn = isOn;
        _isLoading = false;
      });
      if (isOn && !_isConnected) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(seconds: 2));
        FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
      } else {
        await FlutterBluePlus.stopScan();
      }
    });
    FlutterBluePlus.isOn.then((isOn) {
      setState(() {
        _isBluetoothOn = isOn;
        _isLoading = false;
      });
      if (isOn && !_isConnected) {
        FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      }
    });
  }

  void _refreshScan() async {
    if (_isBluetoothOn) {
      setState(() {
        _isLoading = true;
      });
      await FlutterBluePlus.stopScan();
      await Future.delayed(
        const Duration(milliseconds: 300),
      ); // ensure scan stops
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Save device info to file
  Future<void> _saveDeviceProfile(BluetoothDevice device) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/printer_device.json');
    final data = {'id': device.remoteId.str, 'name': device.platformName};
    await file.writeAsString(jsonEncode(data));
  }

  // Load device info from file
  Future<Map<String, dynamic>?> _loadDeviceProfile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/printer_device.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _connectSerial(BluetoothDevice device) async {
    try {
      await device.connect();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If prompted, please enter the PIN in the system dialog.',
          ),
        ),
      );

      List<BluetoothService> services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid.str.toLowerCase() == serialServiceUUID,
        orElse: () => throw Exception('Serial service not found'),
      );
      final characteristic = service.characteristics.firstWhere(
        (c) => c.uuid.str.toLowerCase() == serialCharUUID,
        orElse: () => throw Exception('Serial characteristic not found'),
      );
      setState(() {
        _isConnected = true;
        _connectedDevice = device;
        _serialCharacteristic = characteristic;
      });
      await FlutterBluePlus.stopScan();
      // Save device profile for future auto-connect
      await _saveDeviceProfile(device);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${device.platformName}')),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PrintTextPage(
            serialCharacteristic: _serialCharacteristic!,
            device: _connectedDevice!,
            imageBytes: widget.imageBytes,
          ),
        ),
      );
      setState(() {
        _isConnected = false;
        _connectedDevice = null;
        _serialCharacteristic = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to connect: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Bluetooth Devices')),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Trying to auto-connect to your saved printer...\nPlease wait or turn on your printer.',
                  ),
                ],
              ),
            )
          : !_isBluetoothOn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Bluetooth is off. Please enable Bluetooth.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      await FlutterBluePlus.turnOn();
                    },
                    child: const Text('Turn On Bluetooth'),
                  ),
                ],
              ),
            )
          : _isConnected
          ? const Center(child: Text('Connected to printer.'))
          : StreamBuilder<List<ScanResult>>(
              stream: FlutterBluePlus.scanResults,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final results = snapshot.data!;
                if (results.isEmpty) {
                  return const Center(child: Text('No devices found.'));
                }
                results.sort((a, b) => b.rssi.compareTo(a.rssi));
                return ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final scanResult = results[index];
                    final device = scanResult.device;
                    final advName = scanResult.advertisementData.advName;
                    final address = device.remoteId.str;
                    final name = advName.isNotEmpty ? advName : address;
                    if (advName.isEmpty) {
                      return const SizedBox.shrink();
                    } else {
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(name),
                        subtitle: Text('$address • RSSI: ${scanResult.rssi}'),
                        onTap: () async {
                          final shouldConnect = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Pair and Connect'),
                              content: Text(
                                'Do you want to pair and connect to "$name"?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Connect'),
                                ),
                              ],
                            ),
                          );
                          if (shouldConnect == true) {
                            await _connectSerial(device);
                          }
                        },
                      );
                    }
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.refresh),
        onPressed: _refreshScan,
        tooltip: 'Rescan',
      ),
    );
  }
}
