// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/utils/smi_watermark.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SmiWatermark {
  /// Adiciona marca-d'água com:
  /// - LOGO no canto superior esquerdo
  /// - OS no canto inferior direito
  /// - Sem data/hora
  static Future<File> addWatermark({
    required File original,
    required String osLabel,
    required String tipo,  // mantidos para compatibilidade
    required String setor, // (não usamos aqui)
    DateTime? dateTime,    // ignorado (sem data/hora)
  }) async {
    // Carrega imagem original
    final bytes = await original.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final ui.Image uiImage = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(
        0,
        0,
        uiImage.width.toDouble(),
        uiImage.height.toDouble(),
      ),
    );

    // Desenha a imagem original
    final paint = ui.Paint();
    canvas.drawImage(uiImage, ui.Offset.zero, paint);

    // =========================
    // LOGO NO CANTO SUPERIOR ESQUERDO
    // =========================

    // Certifique-se que o arquivo existe em: assets/logo_smi.png
    final logoData = await rootBundle.load('assets/logo.png');
    final logoBytes = logoData.buffer.asUint8List();

    final logoCodec = await ui.instantiateImageCodec(logoBytes);
    final logoFrame = await logoCodec.getNextFrame();
    final ui.Image logoImg = logoFrame.image;

    // Tamanho alvo ~12% da largura da foto
    final double targetLogoWidth = uiImage.width * 0.12;
    final double logoScale = targetLogoWidth / logoImg.width;

    final ui.Rect srcLogoRect = ui.Rect.fromLTWH(
      0,
      0,
      logoImg.width.toDouble(),
      logoImg.height.toDouble(),
    );

    final ui.Rect dstLogoRect = ui.Rect.fromLTWH(
      20, // margem esquerda
      20, // margem topo
      logoImg.width * logoScale,
      logoImg.height * logoScale,
    );

    final ui.Paint logoPaint = ui.Paint()
      ..isAntiAlias = true
      ..filterQuality = ui.FilterQuality.high
      ..color = ui.Color.fromARGB(220, 255, 255, 255); // leve opacidade

    canvas.drawImageRect(
      logoImg,
      srcLogoRect,
      dstLogoRect,
      logoPaint,
    );

    // =========================
    // TEXTO DA OS NO CANTO INFERIOR DIREITO
    // =========================

    final painting.TextPainter textPainter = painting.TextPainter(
      text: painting.TextSpan(
        text: osLabel, // Ex: "OS 2025/0001"
        style: const painting.TextStyle(
          color: ui.Color.fromARGB(230, 255, 255, 255),
          fontSize: 52,
          fontWeight: painting.FontWeight.bold,
          shadows: [
            painting.Shadow(
              offset: ui.Offset(3, 3),
              blurRadius: 6,
              color: ui.Color.fromARGB(160, 0, 0, 0),
            ),
          ],
        ),
      ),
      textDirection: painting.TextDirection.ltr,
    );

    textPainter.layout(
      maxWidth: uiImage.width.toDouble(),
    );

    const double margin = 40;
    final ui.Offset osOffset = ui.Offset(
      uiImage.width - textPainter.width - margin,
      uiImage.height - textPainter.height - margin,
    );

    textPainter.paint(canvas, osOffset);

    // =========================
    // FINALIZA E SALVA PNG
    // =========================

    final ui.Picture picture = recorder.endRecording();
    final ui.Image finalImage =
    await picture.toImage(uiImage.width, uiImage.height);

    final ByteData? pngBytes =
    await finalImage.toByteData(format: ui.ImageByteFormat.png);

    final tempDir = await getTemporaryDirectory();
    final baseName = p.basenameWithoutExtension(original.path);
    final outPath = p.join(
      tempDir.path,
      '${baseName}_smi_wm_${DateTime.now().microsecondsSinceEpoch}.png',
    );

    final File newFile = File(outPath);
    await newFile.writeAsBytes(pngBytes!.buffer.asUint8List(), flush: true);

    try {
      uiImage.dispose();
      logoImg.dispose();
      finalImage.dispose();
    } catch (_) {}

    return newFile;
  }
}
