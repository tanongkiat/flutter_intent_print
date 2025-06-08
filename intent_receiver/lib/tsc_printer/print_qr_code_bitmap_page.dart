import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'package:qr/qr.dart';
import 'package:image/image.dart' as img;

class PrintQrCodeBitmapPage extends StatefulWidget {
  final BluetoothCharacteristic serialCharacteristic;
  final BluetoothDevice device;
  const PrintQrCodeBitmapPage({
    super.key,
    required this.serialCharacteristic,
    required this.device,
  });

  @override
  State<PrintQrCodeBitmapPage> createState() => _PrintQrCodeBitmapPageState();
}

class _PrintQrCodeBitmapPageState extends State<PrintQrCodeBitmapPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isPrinting = false;

  Future<List<int>> _buildQrCodeBitmapTspl(
    String data, {
    int cellSize = 10,
    double labelWidthMm = 72,
    double labelHeightMm = 50,
    int printerDpi = 203,
  }) async {
    // 1. Generate QR code matrix

    final qrCode = QrCode(4, QrErrorCorrectLevel.L);
    qrCode.addData(data);
    final qrImage = QrImage(qrCode);
    final moduleCount = qrImage.moduleCount;
    // 2. Create image and draw QR code
    final size = moduleCount * cellSize;
    const int padPx = 5;

    final load_QR = img.Image(
      width: size + (6 * padPx),
      height: size + (2 * padPx),
    );

    img.fill(load_QR, color: img.ColorRgb8(255, 255, 255)); // White background

    for (int x = 0; x < moduleCount; x++) {
      for (int y = 0; y < moduleCount; y++) {
        if (qrImage.isDark(y, x)) {
          img.fillRect(
            load_QR,
            x1: (x * cellSize) + padPx,
            y1: (y * cellSize) + padPx,
            x2: (x + 1) * cellSize + padPx - 1,
            y2: (y + 1) * cellSize + padPx - 1,
            color: img.ColorRgb8(0, 0, 0), // Black square
          );
        }
      }
    }
    //2.1 Resize to some specific width

    // Resize image to width 100px, keep aspect ratio
    final int targetWidth = 150;
    final int targetHeight = ((load_QR!.height * targetWidth) / load_QR.width)
        .round();
    img.Image imgQR = img.copyResize(
      load_QR,
      width: targetWidth,
      height: targetHeight,
    );

    // 3. Convert to 1-bit bitmap for TSPL
    int width = ((imgQR.width + 7) ~/ 8) * 8;
    int height = imgQR.height;

    List<int> bitmap = [];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x += 8) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          int px = (x + bit);
          int newR = 255, newG = 255, newB = 255;
          if (px < imgQR.width) {
            final pixel = imgQR.getPixelSafe(x + bit, y);
            newR = pixel.r.toInt();
            newG = pixel.g.toInt();
            newB = pixel.b.toInt();
          }
          int luma = ((newR * 299) + (newG * 587) + (newB * 114)) ~/ 1000;
          if (luma >= 128) {
            byte |= (1 << (7 - bit));
          }
        }
        bitmap.add(byte);
      }
    }

    // 4. Calculate centering offset
    labelHeightMm = imgQR.height * 25.4 / printerDpi;
    final labelWidthPx = (labelWidthMm * printerDpi / 25.4).round();
    final xOffset = ((labelWidthPx - width) / 2).round().clamp(0, labelWidthPx);
    //final xOffset = 0;
    // 5. Build TSPL command
    final cmd = StringBuffer();
    cmd.writeln('SIZE $labelWidthMm mm,$labelHeightMm mm');
    cmd.writeln('GAP 0 mm,0 mm');
    cmd.writeln('SPEED 4');
    cmd.writeln('DENSITY 12');
    cmd.writeln('CODEPAGE UTF-8');
    cmd.writeln('SET TEAR ON');
    cmd.writeln('SET CUTTER OFF');
    cmd.writeln('DIRECTION 0');
    cmd.writeln('CLS');
    cmd.writeln('BITMAP $xOffset,0,${width ~/ 8},$height,1,');
    List<int> tspl = List<int>.from(ascii.encode(cmd.toString()));
    tspl.addAll(bitmap);
    tspl.addAll(ascii.encode('\nPRINT 1,1\n'));
    return tspl;
  }

  Future<void> _printQrBitmap(String data) async {
    setState(() => _isPrinting = true);
    try {
      final tsplData = await _buildQrCodeBitmapTspl(data, cellSize: 8);

      // Debug: Print bytes as hex
      print(
        'TSPL bytes (hex): ${tsplData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );

      // Debug: Print as ASCII (may not show binary bitmap data correctly)
      print(
        'TSPL as String: ${ascii.decode(tsplData.where((b) => b >= 32 && b <= 126).toList(), allowInvalid: true)}',
      );

      const int chunkSize = 200;
      for (int i = 0; i < tsplData.length; i += chunkSize) {
        final chunk = tsplData.sublist(
          i,
          i + chunkSize > tsplData.length ? tsplData.length : i + chunkSize,
        );
        await widget.serialCharacteristic.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 20));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR bitmap print command sent!')),
      );
    } catch (e, stack) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to print QR bitmap: $e')));
      print(e);
      print(stack);
    }
    setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Print QR Code as Bitmap')),
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
                icon: const Icon(Icons.qr_code_2),
                label: _isPrinting
                    ? const Text('Printing...')
                    : const Text('Print QR Bitmap'),
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
                        await _printQrBitmap(text);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
