import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Minimal QR renderer (package:qr) used to show the pairing code.
class QrCodeView extends StatelessWidget {
  const QrCodeView({super.key, required this.data, this.size = 200});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: QrErrorCorrectLevel.medium);
    final image = QrImage(code);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _QrPainter(image), size: Size.square(size)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final cell = size.width / count;
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < count; y++) {
      for (var x = 0; x < count; x++) {
        if (image.isDark(y, x)) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.image != image;
}
