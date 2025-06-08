import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:image/src/formats/formats.dart';
import 'print_bitmap_page.dart';
import 'print_qr_code_page.dart';
import 'print_barcode_page.dart';
import 'print_qr_code_bitmap_page.dart';
import 'print_receipt_page.dart';
import 'print_receipt_qr_page.dart';
import 'print_bitmap_page_bw.dart';
import 'print_bitmap_from_intent_page.dart';

class PrintTextPage extends StatefulWidget {
  final BluetoothCharacteristic serialCharacteristic;
  final BluetoothDevice device;
  final Uint8List? imageBytes; // <-- make sure it's nullable if needed
  const PrintTextPage({
    super.key,
    required this.serialCharacteristic,
    required this.device,
    this.imageBytes,
  });

  @override
  State<PrintTextPage> createState() => _PrintTextPageState();
}

class _PrintTextPageState extends State<PrintTextPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isPrinting = false;

  List<int> _buildTsplCommand(String text) {
    final cmd = '''
SIZE 72 mm,10 mm
GAP 0 mm,0 mm
SPEED 4
DENSITY 12
CODEPAGE UTF-8
SET TEAR ON
SET CUTTER OFF
CLS
DIRECTION 0
TEXT 100,20,"courmon.TTF",0,12,12,"''';

    final endCmd = '''"
PRINT 1,1
SIZE 72 mm, 10 mm
GAP 0 mm, 0 mm
''';

    // Encode the command up to the text, then the text as UTF-8, then the rest as ASCII
    List<int> bytes = [];
    bytes.addAll(ascii.encode(cmd));
    bytes.addAll(utf8.encode(text));
    bytes.addAll(ascii.encode(endCmd));
    return bytes;
  }

  Future<void> _printText(String text) async {
    setState(() => _isPrinting = true);
    try {
      final textData = _buildTsplCommand(text);
      await widget.serialCharacteristic.write(textData, withoutResponse: true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Print command sent!')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to print: $e')));
    }
    setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    final buttonList = [
      {
        'icon': Icons.image,
        'label': 'Print Bitmap from Asset',
        'onPressed': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrintBitmapPage(
                serialCharacteristic: widget.serialCharacteristic,
                device: widget.device,
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.qr_code,
        'label': 'Print QR Code',
        'onPressed': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrintQrCodePage(
                serialCharacteristic: widget.serialCharacteristic,
                device: widget.device,
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.barcode_reader,
        'label': 'Print Barcode',
        'onPressed': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrintBarcodePage(
                serialCharacteristic: widget.serialCharacteristic,
                device: widget.device,
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.qr_code_2,
        'label': 'Print QR Bitmap',
        'onPressed': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrintQrCodeBitmapPage(
                serialCharacteristic: widget.serialCharacteristic,
                device: widget.device,
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.receipt_long,
        'label': 'Print Receipt',
        'onPressed': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrintReceiptPage(
                serialCharacteristic: widget.serialCharacteristic,
                device: widget.device,
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.qr_code_2,
        'label': 'Print Receipt QR',
        'onPressed': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrintReceiptQrPage(
                serialCharacteristic: widget.serialCharacteristic,
                device: widget.device,
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.image_aspect_ratio,
        'label': 'Print Screen as Bitmap BW',
        'onPressed': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrintBitmapPageBW(
                serialCharacteristic: widget.serialCharacteristic,
                device: widget.device,
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.print,
        'label': 'Print Image from Intent',
        'onPressed': widget.imageBytes == null
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrintBitmapFromIntentPage(
                      serialCharacteristic: widget.serialCharacteristic,
                      device: widget.device,
                      imageBytes: widget.imageBytes!,
                    ),
                  ),
                );
              },
      },
      {
        'icon': Icons.image,
        'label': 'Show Image from Intent',
        'onPressed': widget.imageBytes == null
            ? null
            : () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    content: Image.memory(widget.imageBytes!),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Print Text')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Enter text to print',
                  border: OutlineInputBorder(),
                ),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.print),
                  label: _isPrinting
                      ? const Text('Printing...')
                      : const Text('Print'),
                  onPressed: _isPrinting
                      ? null
                      : () async {
                          final text = _controller.text.trim();
                          if (text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter some text.'),
                              ),
                            );
                            return;
                          }
                          await _printText(text);
                        },
                ),
              ),
              const SizedBox(height: 20),
              // 2-column grid for print option buttons
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.7,
                children: buttonList.map((btn) {
                  return ElevatedButton.icon(
                    icon: Icon(btn['icon'] as IconData),
                    label: Text(btn['label'] as String),
                    onPressed: btn['onPressed'] as void Function()?,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
