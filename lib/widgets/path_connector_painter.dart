import 'package:flutter/material.dart';

class PathConnectorPainter extends CustomPainter {
  final double startX;
  final double endX;
  final Color color;

  const PathConnectorPainter({
    required this.startX,
    required this.endX,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth =
          2.5 // Тонкая линия (было 7.0)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Тропа должна рисоваться только внутри своей полосы 44px.
    //
    // CustomPaint НЕ обрезает рисование, а раньше линия намеренно выходила за
    // границы (start y = -2.5, end y = height + 2.5) ради «отсутствия зазоров».
    // Из-за этого штрихи вместе со скруглёнными концами (ещё ~1.25px) ложились
    // ПОВЕРХ кружков-узлов: кружок рисуется раньше, тропа — после.
    // Теперь концы упираются точно в границы полосы, которые совпадают с
    // краями кружков, а клип гарантирует, что ничего не вылезет наружу.
    canvas.clipRect(Offset.zero & size);

    final start = Offset(size.width / 2 + startX, 0);
    final end = Offset(size.width / 2 + endX, size.height);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx,
        size.height * 0.5,
        end.dx,
        size.height * 0.5,
        end.dx,
        end.dy,
      );

    // Превращаем кривую Безье в аккуратный пунктир
    const double dashWidth = 5.0;
    const double dashSpace = 4.0;
    final dashedPath = Path();

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double nextDistance = distance + dashWidth;
        dashedPath.addPath(
          metric.extractPath(distance, nextDistance.clamp(0.0, metric.length)),
          Offset.zero,
        );
        distance = nextDistance + dashSpace;
      }
    }

    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant PathConnectorPainter oldDelegate) =>
      oldDelegate.startX != startX ||
      oldDelegate.endX != endX ||
      oldDelegate.color != color;
}
