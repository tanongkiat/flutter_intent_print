import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PrintBitmapPageBW extends StatefulWidget {
  final BluetoothCharacteristic serialCharacteristic;
  final BluetoothDevice device;
  const PrintBitmapPageBW({
    super.key,
    required this.serialCharacteristic,
    required this.device,
  });

  @override
  State<PrintBitmapPageBW> createState() => _PrintBitmapPageBWState();
}

class _PrintBitmapPageBWState extends State<PrintBitmapPageBW> {
  bool _isPrinting = false;
  final GlobalKey _repaintKey = GlobalKey();

  Future<Uint8List?> _capturePng() async {
    try {
      // Wait for the next frame to ensure rendering is complete
      await Future.delayed(const Duration(milliseconds: 100));
      RenderRepaintBoundary boundary =
          _repaintKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print(e);
      return null;
    }
  }

  Future<List<int>> _buildTsplBitmapCommandBWFromScreen(
    Uint8List pngBytes,
  ) async {
    final img.Image? src = img.decodeImage(pngBytes);

    // Resize image to width 100px, keep aspect ratio
    final int targetWidth_in_mm = 40; // 71 mm is 200px at 203 DPI
    final int targetWidth = ((targetWidth_in_mm * 203) / 25.4).round();
    final int targetHeight = ((src!.height * targetWidth) / src.width).round();
    img.Image resized = img.copyResize(
      src!,
      width: targetWidth,
      height: targetHeight,
    );

    // Convert to grayscale
    img.Image mono = img.grayscale(resized);

    // Manual threshold to black & white (luma < 128 is black, else white)
    for (int y = 0; y < mono.height; y++) {
      for (int x = 0; x < mono.width; x++) {
        int pixelRed = mono.getPixelSafe(x, y).r.toInt();
        int pixelGreen = mono.getPixelSafe(x, y).g.toInt();
        int pixelBlue = mono.getPixelSafe(x, y).b.toInt();
        int luma =
            ((pixelRed * 299) + (pixelGreen * 587) + (pixelBlue * 114)) ~/ 1000;
        int newR = 0, newG = 0, newB = 0;
        if (luma < 200) {
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
          int newR = 255, newG = 255, newB = 255;
          if (px < mono.width) {
            final pixel = mono.getPixelSafe(x + bit, y);
            newR = pixel.r.toInt();
            newG = pixel.g.toInt();
            newB = pixel.b.toInt();
          }
          int luma = ((newR * 299) + (newG * 587) + (newB * 114)) ~/ 1000;
          // too dark I will need to convert it //
          // if (luma < 128) {
          // 128 is too much :P
          if (luma >= 128) {
            byte |= (1 << (7 - bit));
          }
        }
        bitmap.add(byte);
      }
    }

    //     mm = pixel * 25.4 / printerDpi;

    final width_in_mm = (targetWidth * 25.4) / 203;
    final height_in_mm = (targetHeight * 25.4) / 203;

    final cmd = StringBuffer();
    cmd.writeln('SIZE ${width_in_mm} mm,$height_in_mm mm');
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
    tspl.addAll(
      ascii.encode('\nTEXT 100,20,"courmon.TTF",0,12,12,"Print Screen"'),
    );
    tspl.addAll(ascii.encode('\nPRINT 1,1\n'));
    return tspl;
  }

  Future<void> _printBitmapBWFromScreen() async {
    setState(() => _isPrinting = true);
    try {
      final pngBytes = await _capturePng();
      if (pngBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to capture screen!')),
        );
        setState(() => _isPrinting = false);
        return;
      }
      final tsplData = await _buildTsplBitmapCommandBWFromScreen(pngBytes);

      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not get the Downloads directory');
      }
      final filePath = '${downloadsDir.path}/capturescreen.bin';
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
        const SnackBar(content: Text('Bitmap BW print command sent!')),
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
    return RepaintBoundary(
      key: _repaintKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Print Bitmap BW From Screen')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'This area will be captured and printed as bitmap.',
                      style: TextStyle(fontSize: 18, color: Colors.black),
                    ),
                    SizedBox(height: 10),
                    FlutterLogo(size: 60),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.print),
                  label: _isPrinting
                      ? const Text('Printing...')
                      : const Text('Print Screen as Bitmap BW'),
                  onPressed: _isPrinting ? null : _printBitmapBWFromScreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
