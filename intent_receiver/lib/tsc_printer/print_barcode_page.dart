import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';

class PrintBarcodePage extends StatefulWidget {
  final BluetoothCharacteristic serialCharacteristic;
  final BluetoothDevice device;
  const PrintBarcodePage({
    super.key,
    required this.serialCharacteristic,
    required this.device,
  });

  @override
  State<PrintBarcodePage> createState() => _PrintBarcodePageState();
}

class _PrintBarcodePageState extends State<PrintBarcodePage> {
  final TextEditingController _controller = TextEditingController();
  bool _isPrinting = false;

  List<int> _buildTsplBarcodeCommand(String data) {
    final cmd =
        '''
SIZE 72 mm,30 mm
GAP 0 mm,0 mm
SPEED 4
DENSITY 12
CODEPAGE UTF-8
SET TEAR ON
SET CUTTER OFF
CLS
DIRECTION 0
BARCODE 100,100,"128",100,1,0,2,2,"$data"
PRINT 1,1
''';
    return ascii.encode(cmd);
  }

  Future<void> _printBarcode(String data) async {
    setState(() => _isPrinting = true);
    try {
      final tsplData = _buildTsplBarcodeCommand(data);
      await widget.serialCharacteristic.write(tsplData, withoutResponse: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Barcode print command sent!')),
      );
    } catch (e, stack) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to print barcode: $e')));
      print(e);
      print(stack);
    }
    setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Print Barcode')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Enter text for Barcode',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(
                  Icons.qr_code,
                ), // <-- changed from Icons.barcode
                label: _isPrinting
                    ? const Text('Printing...')
                    : const Text('Print Barcode'),
                onPressed: _isPrinting
                    ? null
                    : () async {
                        final text = _controller.text.trim();
                        if (text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter text for barcode.'),
                            ),
                          );
                          return;
                        }
                        await _printBarcode(text);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
