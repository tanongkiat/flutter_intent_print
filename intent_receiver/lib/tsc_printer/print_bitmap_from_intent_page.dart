import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class PrintBitmapFromIntentPage extends StatefulWidget {
  final BluetoothCharacteristic serialCharacteristic;
  final BluetoothDevice device;
  final Uint8List imageBytes;
  const PrintBitmapFromIntentPage({
    super.key,
    required this.serialCharacteristic,
    required this.device,
    required this.imageBytes,
  });

  @override
  State<PrintBitmapFromIntentPage> createState() =>
      _PrintBitmapFromIntentPageState();
}

class _PrintBitmapFromIntentPageState extends State<PrintBitmapFromIntentPage> {
  bool _isPrinting = false;

  Future<List<int>> _buildTsplBitmapCommandBWFromIntent(
    Uint8List pngBytes,
  ) async {
    final img.Image? decoded_img = img.decodeImage(pngBytes);
    // If the image has an alpha channel, flatten it onto a white background
    if (decoded_img == null) {
      throw Exception('Failed to decode image from intent');
    }
    final img.Image whiteBg = img.Image(
      width: decoded_img.width,
      height: decoded_img.height,
    );
    // Fill with white
    // img.fill(whiteBg, color: img.ColorRgb8(255, 255, 255));
    // Composite the PNG over the white background
    int lastR = 0;
    int countR = 0;
    for (int y = 0; y < decoded_img.height; y++) {
      for (int x = 0; x < decoded_img.width; x++) {
        final pixel = decoded_img.getPixelSafe(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final a = pixel.a.toInt();
        if (r != lastR) {
          countR++;
          lastR = r;
        }
        whiteBg.setPixelRgba(x, y, r, g, b, a);
      }
    }
    final img.Image src = decoded_img;
    debugPrint("Decoded image width: ${src.width}, height: ${src.height}");
    debugPrint("Unique red values: $countR");

    // Resize image to width 100px, keep aspect ratio
    final int targetWidth_in_mm = 40; // 71 mm is 200px at 203 DPI
    final int targetWidth = ((targetWidth_in_mm * 203) / 25.4).round();
    final int targetHeight = ((src!.height * targetWidth) / src.width).round();
    img.Image resized = img.copyResize(
      src,
      width: targetWidth,
      height: targetHeight,
    );

    // Convert to grayscale
    img.Image mono = img.grayscale(resized);

    // Manual threshold to black & white (luma < 200 is black, else white)
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
          if (luma >= 128) {
            byte |= (1 << (7 - bit));
          }
        }
        bitmap.add(byte);
      }
    }

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
      ascii.encode('\nTEXT 50,20,"courmon.TTF",0,12,12,"Print Intent Image"'),
    );
    tspl.addAll(ascii.encode('\nPRINT 1,1\n'));
    return tspl;
  }

  Future<void> _printBitmapBWFromIntent() async {
    setState(() => _isPrinting = true);
    try {
      final tsplData = await _buildTsplBitmapCommandBWFromIntent(
        widget.imageBytes,
      );

      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not get the Downloads directory');
      }
      final filePath = '${downloadsDir.path}/intent_image.bin';
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
      // Return to the app that sent the intent
      SystemNavigator.pop();
    } catch (e, stack) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to print bitmap: $e')));
      print(e.toString());
      print(stack);
      // Also return to the app on error
      SystemNavigator.pop();
    }
    setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Print Bitmap From Intent')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: widget.imageBytes.isNotEmpty
                  ? Image.memory(widget.imageBytes, height: 180)
                  : const Text('No image data.'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.print),
                label: _isPrinting
                    ? const Text('Printing...')
                    : const Text('Print Intent Image as Bitmap BW'),
                onPressed: _isPrinting ? null : _printBitmapBWFromIntent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
