import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PrintBitmapPage extends StatefulWidget {
  final BluetoothCharacteristic serialCharacteristic;
  final BluetoothDevice device;
  const PrintBitmapPage({
    super.key,
    required this.serialCharacteristic,
    required this.device,
  });

  @override
  State<PrintBitmapPage> createState() => _PrintBitmapPageState();
}

class _PrintBitmapPageState extends State<PrintBitmapPage> {
  bool _isPrinting = false;

  Future<List<int>> _buildTsplBitmapCommand(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final img.Image? src = img.decodeImage(bytes);

    // Resize image to width 100px, keep aspect ratio
    final int targetWidth = 100;
    final int targetHeight = ((src!.height * targetWidth) / src.width).round();
    img.Image resized = img.copyResize(
      src,
      width: targetWidth,
      height: targetHeight,
    );

    // Convert to grayscale
    img.Image mono = img.grayscale(resized);

    // Manual threshold to black & white
    for (int y = 0; y < mono.height; y++) {
      for (int x = 0; x < mono.width; x++) {
        int pixelRed = mono.getPixelSafe(x, y).r.toInt();
        int pixelGreen = mono.getPixelSafe(x, y).g.toInt();
        int pixelBlue = mono.getPixelSafe(x, y).b.toInt();
        int luma =
            ((pixelRed * 299) + (pixelGreen * 587) + (pixelBlue * 114)) ~/ 1000;
        int newR = 0;
        int newG = 0;
        int newB = 0;
        if (luma < 128) {
          newR = 0;
          newG = 0;
          newB = 0;
        } else {
          newR = 255;
          newG = 255;
          newB = 255;
        }
        mono.setPixelRgb(x, y, newR, newG, newB);
      }
    }

    int width = ((mono.width + 7) ~/ 8) * 8;
    int height = mono.height;

    List<int> bitmap = [];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x += 8) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          int px = (x + bit);
          int newR = 0, newG = 0, newB = 0;

          if (px < mono.width) {
            newR = mono.getPixelSafe(x + bit, y).r.toInt();
            newG = mono.getPixelSafe(x + bit, y).g.toInt();
            newB = mono.getPixelSafe(x + bit, y).b.toInt();
          } else {
            newR = 255;
            newG = 255;
            newB = 255;
          }

          int luma = ((newR * 299) + (newG * 587) + (newB * 114)) ~/ 1000;
          if (luma >= 128) {
            byte |= (1 << (7 - bit));
          }
        }
        bitmap.add(byte);
      }
    }

    final cmd = StringBuffer();
    cmd.writeln('SIZE ${width ~/ 8} mm,$height mm');
    cmd.writeln('GAP 0 mm,0 mm');
    cmd.writeln('SPEED 4');
    cmd.writeln('DENSITY 12');
    cmd.writeln('CODEPAGE UTF-8');
    cmd.writeln('SET TEAR OFF');
    cmd.writeln('SET CUTTER OFF');
    cmd.writeln('DIRECTION 0');
    cmd.writeln('CLS');
    cmd.writeln('BITMAP 0,0,${width ~/ 8},$height,1,');
    List<int> tspl = List<int>.from(ascii.encode(cmd.toString()));
    tspl.addAll(bitmap);
    tspl.addAll(ascii.encode('\nTEXT 100,20,"courmon.TTF",0,7,7,"Bitmap"'));
    tspl.addAll(ascii.encode('\nPRINT 1,1\n'));
    return tspl;
  }

  Future<void> _printBitmap() async {
    setState(() => _isPrinting = true);
    try {
      final tsplData = await _buildTsplBitmapCommand('assets/logo.bmp');

      // Get the Downloads directory
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not get the Downloads directory');
      }
      final filePath = '${downloadsDir.path}/tspldata.bin';
      final file = File(filePath);
      await file.writeAsBytes(tsplData);
      print('TSPL data exported to $filePath');

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
        SnackBar(content: Text('Bitmap print command sent!\nFile: $filePath')),
      );
    } catch (e, stack) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to print bitmap: $e')));
      print(e.toString());
      print(stack);
    }
    setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Print Bitmap')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Print bitmap from assets/logo.png'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.image),
                label: _isPrinting
                    ? const Text('Printing...')
                    : const Text('Print Bitmap'),
                onPressed: _isPrinting ? null : _printBitmap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
