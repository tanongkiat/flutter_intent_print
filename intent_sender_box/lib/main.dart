import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart'; // <-- Add this line

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey _imageKey = GlobalKey();

  Future<void> _sendIntent() async {
    try {
      // Ensure the context is available and attached
      final context = _imageKey.currentContext;
      if (context == null) {
        ScaffoldMessenger.of(
          this.context,
        ).showSnackBar(const SnackBar(content: Text('Image not ready')));
        return;
      }
      final boundary = context.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        ScaffoldMessenger.of(
          this.context,
        ).showSnackBar(const SnackBar(content: Text('Boundary not found')));
        return;
      }
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      Uint8List imageBytes = byteData!.buffer.asUint8List();

      // Send image bytes via MethodChannel
      const platform = MethodChannel('com.example.intent_sender_box/image');
      await platform.invokeMethod('sendImageBytes', imageBytes);

      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('Image bytes sent via MethodChannel')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        this.context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Square image wrapped with RepaintBoundary for capture
            RepaintBoundary(
              key: _imageKey,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white, // Ensure the background is white
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white, // White border
                    width: 20, // 20 pixel border
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CustomPaint(
                    size: const Size(200, 200),
                    painter: _StripePainter(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Send Intent button
            ElevatedButton(
              onPressed: _sendIntent,
              child: const Text('Send Intent'),
            ),
          ],
        ),
      ),
    );
  }
}

// Add this class at the end of your file
class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stripeWidth = 20.0;
    final paint = Paint();

    for (int i = 0; i < size.width / stripeWidth; i++) {
      paint.color = i.isEven ? Colors.black : Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(i * stripeWidth, 0, stripeWidth, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
