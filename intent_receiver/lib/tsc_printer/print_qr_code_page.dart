import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';

class PrintQrCodePage extends StatefulWidget {
  final BluetoothCharacteristic serialCharacteristic;
  final BluetoothDevice device;
  const PrintQrCodePage({
    super.key,
    required this.serialCharacteristic,
    required this.device,
  });

  @override
  State<PrintQrCodePage> createState() => _PrintQrCodePageState();
}

class _PrintQrCodePageState extends State<PrintQrCodePage> {
  final TextEditingController _controller = TextEditingController();
  bool _isPrinting = false;

  List<int> _buildTsplQrCommand(String data) {
    final cmd =
        '''
SIZE 72 mm,20 mm
GAP 0 mm,0 mm
SPEED 4
DENSITY 12
DIRECTION 0
CLS
QRCODE 10,10,M,5,M,0,M2,S7," $data"
PRINT 1,1
''';
    List<int> bytes = [];
    bytes.addAll(ascii.encode(cmd));
    //    bytes.addAll(utf8.encode(qr_cmd));
    //    bytes.addAll(ascii.encode(end_cmd));
    return bytes;
  }

  Future<void> _printQrCode(String data) async {
    setState(() => _isPrinting = true);
    try {
      final tsplData = _buildTsplQrCommand(data);
      await widget.serialCharacteristic.write(tsplData, withoutResponse: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR code print command sent!')),
      );
    } catch (e, stack) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to print QR code: $e')));
      print(e);
      print(stack);
    }
    setState(() => _isPrinting = false);
  }

  int estimateQrVersion(String data, {String ecc = 'L'}) {
    // Very rough estimate for version, for most short data version 1 is enough
    // For more, see QR code specs or use a QR library
    if (data.length <= 17) return 1;
    if (data.length <= 32) return 2;
    if (data.length <= 53) return 3;
    if (data.length <= 78) return 4;
    if (data.length <= 106) return 5;
    // ...add more as needed
    return 10; // fallback for long data
  }

  double calculateQrHeightMm(String data, {int cellWidth = 7, int dpi = 203}) {
    int version = estimateQrVersion(data);
    int modules = 21 + (version - 1) * 4;
    int heightDots = modules * cellWidth;
    double heightMm = heightDots / dpi * 25.4;
    // Multiply by 3 for safety margin
    return (heightMm * 2.2).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Print QR Code')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Enter text for QR code',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.qr_code),
                label: _isPrinting
                    ? const Text('Printing...')
                    : const Text('Print QR Code'),
                onPressed: _isPrinting
                    ? null
                    : () async {
                        final text = _controller.text.trim();
                        if (text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter text for QR code.'),
                            ),
                          );
                          return;
                        }
                        await _printQrCode(text);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
