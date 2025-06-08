import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

class PrintReceiptPage extends StatefulWidget {
  final BluetoothCharacteristic serialCharacteristic;
  final BluetoothDevice device;
  const PrintReceiptPage({
    super.key,
    required this.serialCharacteristic,
    required this.device,
  });

  @override
  State<PrintReceiptPage> createState() => _PrintReceiptPageState();
}

class _PrintReceiptPageState extends State<PrintReceiptPage> {
  bool _isPrinting = false;

  Future<List<int>> _buildTsplBitmapCommand(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final img.Image? src = img.decodeImage(bytes);

    // Resize image to width 100px, keep aspect ratio
    final int targetWidth = 200;
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
          if (luma < 128) {
            byte |= (1 << (7 - bit));
          }
        }
        bitmap.add(byte);
      }
    }
    final printerDpi = 203; // Default DPI for many TSPL printers
    final labelHeightMm = height * 25.4 / printerDpi;
    final cmd = StringBuffer();
    cmd.writeln('SIZE ${width ~/ 8} mm,$labelHeightMm mm');
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
    // tspl.addAll(ascii.encode('\nTEXT 100,20,"courmon.TTF",0,7,7,"Bitmap"'));
    tspl.addAll(ascii.encode('\nPRINT 1,1\n'));
    return tspl;
  }

  Future<List<int>> _buildTsplReceiptCommand({
    required String header_code,
    required String storeid,
    required String sender_name,
    required String sender_address_line1,
    required String sender_address_line2,
    required String receiver_name,
    required String receiver_address_line1,
    required String receiver_address_line2,
    required String order_type,
    required String footer_code,
  }) async {
    print("header_code: $header_code");
    final cmd_1 = '''
SIZE 72 mm,60 mm
GAP 0 mm,0 mm
SPEED 4
DENSITY 12
CODEPAGE UTF-8
SET TEAR ON
SET CUTTER OFF
CLS"''';

    final cmd_2 =
        '''
SIZE 72 mm, 20 mm
GAP 0 mm,0 mm
SPEED 4
DENSITY 12
CODEPAGE UTF-8
SET TEAR ON
SET CUTTER OFF
CLS
BARCODE 120,20,"128",100,1,0,2,2,"$header_code"
PRINT 1,1
SIZE 72 mm, 50 mm
GAP 0 mm,0 mm
SPEED 4
DENSITY 12
CODEPAGE UTF-8
SET TEAR ON
SET CUTTER OFF
CLS
TEXT 100,50,"courmon.TTF",0,10,10,"''';
    final txt_store = "รหัสสาขาปลายทาง";
    final cmd_3 =
        '''"
TEXT 100,90,"courmon.TTF",0,12,12,"$storeid"
TEXT 100,150,"courmon.TTF",0,10,10,"''';
    final txt_sender = "ผู้ส่ง: $sender_name";
    final cmd_4 = '''"
TEXT 100,180,"courmon.TTF",0,8,8,"''';

    final txt_sender_address_1 = "$sender_address_line1";
    final cmd_5 = '''"
TEXT 100,210,"courmon.TTF",0,8,8,"''';
    final txt_sender_address_2 = "$sender_address_line2";
    final cmd_6 = '''"
TEXT 100,250,"courmon.TTF",0,10,10,"''';
    final txt_receiver = "ผู้รับ: $receiver_name";
    final cmd_7 = '''"
TEXT 100,280,"courmon.TTF",0,8,8,"''';
    final txt_receiver_address_1 = "$receiver_address_line1";
    final cmd_8 = '''"
TEXT 100,310,"courmon.TTF",0,8,8,"''';
    final txt_receiver_address_2 = "$receiver_address_line2";
    final cmd_9 =
        '''"
TEXT 150,360,"courmon.TTF",0,14,14,"$order_type"
PRINT 1,1
SIZE 72 mm, 30 mm
GAP 0 mm,0 mm
SPEED 4
DENSITY 12
CODEPAGE UTF-8
SET TEAR ON
SET CUTTER OFF
CLS
BARCODE 120,20,"128",100,1,0,2,2,"$footer_code"
PRINT 1,1
''';

    List<int> bytes = [];
    List<int> bitmapBytes = await _buildTsplBitmapCommand(
      'assets/speedy_logo.png',
    );
    //    bytes.addAll(ascii.encode(cmd_1));
    bytes.addAll(bitmapBytes);
    //bytes.addAll(utf8.encode(text));
    bytes.addAll(ascii.encode(cmd_2));
    bytes.addAll(utf8.encode(txt_store));
    bytes.addAll(ascii.encode(cmd_3));
    bytes.addAll(utf8.encode(txt_sender));
    bytes.addAll(ascii.encode(cmd_4));
    bytes.addAll(utf8.encode(txt_sender_address_1));
    bytes.addAll(ascii.encode(cmd_5));
    bytes.addAll(utf8.encode(txt_sender_address_2));
    bytes.addAll(ascii.encode(cmd_6));
    bytes.addAll(utf8.encode(txt_receiver));
    bytes.addAll(ascii.encode(cmd_7));
    bytes.addAll(utf8.encode(txt_receiver_address_1));
    bytes.addAll(ascii.encode(cmd_8));
    bytes.addAll(utf8.encode(txt_receiver_address_2));
    bytes.addAll(ascii.encode(cmd_9));

    return bytes;
  }

  Future<void> _printReceipt() async {
    setState(() => _isPrinting = true);
    try {
      List<int> tsplData = await _buildTsplReceiptCommand(
        header_code: "SPCD2505000006579",
        storeid: "16888",
        sender_name: "สวัสดี โลจิสติกส์",
        sender_address_line1: "123 ชนะสงคราม พระนคร",
        sender_address_line2: "กรุงเทพมหานคร 10200",
        receiver_name: "โชคดี ขนส่ง",
        receiver_address_line1: "16888 THE TARA บางตลาด",
        receiver_address_line2: "ปากเกร็ด นนทบุรี 11120",
        order_type: "XS",
        footer_code: "7119900000010",
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
        const SnackBar(content: Text('Receipt print command sent!')),
      );
    } catch (e, stack) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to print receipt: $e')));
      print(e);
      print(stack);
    }
    setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Print Receipt')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Sample Receipt',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.receipt_long),
                label: _isPrinting
                    ? const Text('Printing...')
                    : const Text('Print Receipt'),
                onPressed: _isPrinting ? null : _printReceipt,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
