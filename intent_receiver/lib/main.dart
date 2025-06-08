import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import "tsc_printer/bluetoothscanpage.dart";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const platform = MethodChannel('intent_receiver/imagebytes');
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _requestBluetoothPermissions().then((_) async {
      debugPrint('initState: Calling _getImageBytes()');
      await _getImageBytes();
      await _checkAndRedirectToBluetoothScan();
    });
  }

  Future<void> _requestBluetoothPermissions() async {
    // Request all relevant permissions for Bluetooth (Android 12+ and below)
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
      Permission.locationWhenInUse,
      Permission.locationAlways,
    ].request();

    // Optionally, show a message if any permission is denied
    if (statuses.values.any((status) => !status.isGranted)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth and location permissions are required.'),
          ),
        );
      }
    }
  }

  Future<void> _checkAndRedirectToBluetoothScan() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/device.json');
    if (!await file.exists()) {
      // No saved device, redirect to BluetoothScanPage
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => BluetoothScanPage(imageBytes: _imageBytes),
          ),
        );
      }
    }
  }

  Future<void> _getImageBytes() async {
    debugPrint('_getImageBytes: Invoked');
    try {
      final bytes = await platform.invokeMethod<Uint8List>('getImageBytes');
      debugPrint('_getImageBytes: platform.invokeMethod returned');
      if (bytes != null) {
        debugPrint(
          'Received image bytes: length=${bytes.length}, sample=${bytes.take(20).toList()}',
        );
        setState(() {
          _imageBytes = bytes;
          debugPrint('Set _imageBytes, length: ${_imageBytes?.length}');
        });
        // Show popup dialog with the image
        if (mounted) {
          debugPrint('Showing image dialog');
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              content: Image.memory(bytes),
              actions: [
                TextButton(
                  onPressed: () {
                    debugPrint('Dialog closed');
                    Navigator.of(context).pop();
                  },
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: () {
                    debugPrint('Print button pressed');
                    Navigator.of(context).pop(); // Close the dialog
                    if (_imageBytes != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              BluetoothScanPage(imageBytes: _imageBytes!),
                        ),
                      );
                    }
                  },
                  child: const Text('Print'),
                ),
              ],
            ),
          );
        }
      } else {
        debugPrint('No image bytes received.');
      }
    } on PlatformException catch (e) {
      debugPrint('Error receiving image bytes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('build: _imageBytes is ${_imageBytes?.length}');
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _imageBytes != null
                ? Image.memory(_imageBytes!, height: 200)
                : const Text('No image received via intent.'),
            const SizedBox(height: 24),
            if (_imageBytes != null)
              ElevatedButton(
                onPressed: () {
                  debugPrint('Show Image Dialog button pressed');
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      content: Image.memory(_imageBytes!),
                      actions: [
                        TextButton(
                          onPressed: () {
                            debugPrint('Dialog closed');
                            Navigator.of(context).pop();
                          },
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show Image Dialog'),
              ),
          ],
        ),
      ),
    );
  }
}
