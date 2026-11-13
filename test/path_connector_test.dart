import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:game_of_aim_app/widgets/path_connector_painter.dart';

/// Проверка геометрии пунктирной тропы между квестами.
///
/// Реальный дефект: линия намеренно выходила за свою полосу (y = -2.5 и
/// y = height + 2.5), а CustomPaint не обрезает рисование. Штрихи ложились
/// поверх кружков-узлов, потому что те рисуются раньше.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double stripWidth = 200;
  const double stripHeight = 44;
  const double paddingAbove = 20;
  const double paddingBelow = 20;

  const painter = PathConnectorPainter(
    startX: 60,
    endX: -60,
    color: Color(0xFFFFFFFF),
  );

  /// Рисует тропу на холсте с запасом сверху и снизу и возвращает пиксели.
  Future<ByteData> renderWithMargins() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Сдвигаем полосу вниз, оставив пустое место сверху и снизу: именно туда
    // раньше «вылезала» линия.
    canvas.translate(0, paddingAbove);
    painter.paint(canvas, const Size(stripWidth, stripHeight));

    final image = await recorder.endRecording().toImage(
      stripWidth.toInt(),
      (stripHeight + paddingAbove + paddingBelow).toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!;
  }

  /// Считает непрозрачные пиксели в горизонтальных строках [from, to).
  int opaquePixels(ByteData data, int width, int from, int to) {
    var count = 0;
    for (var y = from; y < to; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        if (data.getUint8(offset + 3) > 0) count++;
      }
    }
    return count;
  }

  test('тропа не рисуется выше своей полосы', () async {
    final data = await renderWithMargins();
    final above = opaquePixels(
      data,
      stripWidth.toInt(),
      0,
      paddingAbove.toInt(),
    );
    expect(
      above,
      0,
      reason:
          'над полосой тропы есть закрашенные пиксели — линия заходит '
          'на кружок-узел, который рисуется раньше неё',
    );
  });

  test('тропа не рисуется ниже своей полосы', () async {
    final data = await renderWithMargins();
    final top = (paddingAbove + stripHeight).toInt();
    final bottom = (stripHeight + paddingAbove + paddingBelow).toInt();
    final below = opaquePixels(data, stripWidth.toInt(), top, bottom);
    expect(below, 0, reason: 'под полосой тропы есть закрашенные пиксели');
  });

  test('внутри полосы тропа действительно рисуется', () async {
    final data = await renderWithMargins();
    final inside = opaquePixels(
      data,
      stripWidth.toInt(),
      paddingAbove.toInt(),
      (paddingAbove + stripHeight).toInt(),
    );
    expect(
      inside,
      greaterThan(0),
      reason: 'тропа не нарисована вообще — проверка выше стала бессмысленной',
    );
  });
}
