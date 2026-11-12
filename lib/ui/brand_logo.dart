import 'package:flutter/material.dart';

/// Logo ShopBook : un sac de boutique blanc sur fond bleu, avec trois barres
/// orange croissantes (le stock et les gains qui montent).
/// Dessiné en code : net à toutes les tailles, et sert à générer les icônes
/// Android / Windows / web (test/tool/generate_icons_test.dart).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72, this.background = true});

  final double size;

  /// false : uniquement le dessin (icône adaptative Android sur fond uni).
  final bool background;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: BrandLogoPainter(background: background));
}

class BrandLogoPainter extends CustomPainter {
  const BrandLogoPainter({this.background = true, this.contentScale = 1});

  final bool background;

  /// Réduit le dessin au centre (zone de sécurité des icônes adaptatives).
  final double contentScale;

  static const blueLight = Color(0xFF1E88E5);
  static const blueDark = Color(0xFF0D47A1);
  static const orange = Color(0xFFFFA000);
  static const orangeLight = Color(0xFFFFCA28);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (background) {
      final bg = RRect.fromRectAndRadius(Offset.zero & Size.square(s), Radius.circular(s * 0.22));
      canvas.drawRRect(
        bg,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [blueLight, blueDark],
          ).createShader(Offset.zero & Size.square(s)),
      );
    }

    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.scale(contentScale);
    canvas.translate(-s / 2, -s / 2);

    Offset p(double x, double y) => Offset(x * s, y * s);

    // Anse fine du sac (entre deux œillets).
    final handle = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.038
      ..strokeCap = StrokeCap.round;
    final handlePath = Path()
      ..moveTo(0.39 * s, 0.41 * s)
      ..lineTo(0.39 * s, 0.30 * s)
      ..arcToPoint(p(0.61, 0.30), radius: Radius.circular(0.11 * s))
      ..lineTo(0.61 * s, 0.41 * s);
    canvas.drawPath(handlePath, handle);

    // Corps évasé (plus large en bas), coins arrondis.
    final r = 0.045 * s;
    final body = Path()
      ..moveTo(0.27 * s + r, 0.34 * s)
      ..lineTo(0.73 * s - r, 0.34 * s)
      ..quadraticBezierTo(0.73 * s, 0.34 * s, 0.735 * s, 0.34 * s + r)
      ..lineTo(0.785 * s, 0.81 * s - r)
      ..quadraticBezierTo(0.79 * s, 0.81 * s, 0.79 * s - r, 0.81 * s)
      ..lineTo(0.21 * s + r, 0.81 * s)
      ..quadraticBezierTo(0.21 * s, 0.81 * s, 0.215 * s, 0.81 * s - r)
      ..lineTo(0.265 * s, 0.34 * s + r)
      ..quadraticBezierTo(0.27 * s, 0.34 * s, 0.27 * s + r, 0.34 * s)
      ..close();
    canvas.drawPath(
      body.shift(Offset(0, s * 0.015)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.02),
    );
    canvas.drawPath(body, Paint()..color = Colors.white);
    // Œillets où passe l'anse.
    final eyelet = Paint()..color = blueDark;
    canvas.drawCircle(p(0.39, 0.41), s * 0.022, eyelet);
    canvas.drawCircle(p(0.61, 0.41), s * 0.022, eyelet);

    // Trois barres croissantes.
    final barPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [orange, orangeLight],
      ).createShader(Rect.fromPoints(p(0.3, 0.45), p(0.7, 0.73)));
    const bottom = 0.73;
    const width = 0.095;
    const bars = [(0.315, 0.11), (0.4525, 0.18), (0.59, 0.27)];
    for (final (x, h) in bars) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromPoints(p(x, bottom - h), p(x + width, bottom)),
          topLeft: Radius.circular(s * 0.02),
          topRight: Radius.circular(s * 0.02),
        ),
        barPaint,
      );
    }
    // Ligne de base (le « carnet »).
    canvas.drawLine(
      p(0.29, bottom + 0.012),
      p(0.71, bottom + 0.012),
      Paint()
        ..color = blueDark
        ..strokeWidth = s * 0.018
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BrandLogoPainter old) =>
      old.background != background || old.contentScale != contentScale;
}
