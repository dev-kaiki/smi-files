// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/utils/os_pdf_export.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/supabase/supabase_manager.dart';

class OsPdfExport {
  OsPdfExport._();

  /// Quantidade máxima de fotos que entram no PDF
  static const int maxImagesInPdf = 45;

  /// Fontes offline (assets)
  static const String _fontRegularAsset = 'assets/fonts/NotoSans-Regular.ttf';
  static const String _fontBoldAsset = 'assets/fonts/NotoSans-Bold.ttf';

  static Future<void> exportOsToPdf({
    required BuildContext context,
    required Map<String, dynamic> osInfo,
    required List<Map<String, dynamic>> mediaFiles,
  }) async {
    try {
      const smiGreenHex = 0xFF00C853;
      final smiGreen = PdfColor.fromInt(smiGreenHex);
      final smiDark = PdfColors.grey800;
      final smiLightBg = PdfColor.fromHex('#F5FAF3');

      // ============================
      // FONTES OFFLINE (com fallback)
      // ============================
      pw.Font? baseFont;
      pw.Font? boldFont;

      try {
        final reg = await rootBundle.load(_fontRegularAsset);
        final bol = await rootBundle.load(_fontBoldAsset);
        baseFont = pw.Font.ttf(reg);
        boldFont = pw.Font.ttf(bol);
      } catch (_) {
        // fallback: usa fonte padrão do pacote pdf
        baseFont = null;
        boldFont = null;
      }

      final pageTheme = pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: (baseFont != null && boldFont != null)
            ? pw.ThemeData.withFont(base: baseFont!, bold: boldFont!)
            : pw.ThemeData.base(),
      );

      // ============================
      // LOGO (asset)
      // ============================
      pw.ImageProvider? logoImage;
      try {
        final data = await rootBundle.load('assets/logo.png');
        logoImage = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {
        logoImage = null;
      }

      final doc = pw.Document();

      final ano = (osInfo['ano'] ?? '').toString();
      final osCode = (osInfo['os_code'] ?? '').toString();
      final tipo = (osInfo['tipo'] ?? '').toString();
      final setor = (osInfo['setor'] ?? '').toString();
      final status = (osInfo['status'] ?? '').toString();

      final defeito = (osInfo['defeito_principal'] ?? '').toString();
      final acao = (osInfo['acao_tomada'] ?? '').toString();
      final pecas = (osInfo['pecas_trocadas'] ?? '').toString();

      final tecnicoNome = (osInfo['tecnico_nome'] ?? '').toString();
      final clientId = (osInfo['client_id'] ?? '').toString();

      // ============================
      // BUSCAR DADOS DA OS (SERVIDOR)
      // ============================
      String serverOsId = (osInfo['os_id'] ?? osInfo['server_os_id'] ?? '').toString();

      String servicoSolicitado = '';
      String servicoExecutado = '';
      String statusArquivo = ''; // inc|alt|exc
      bool deletedServer = false;

      List<Map<String, dynamic>> apontamentos = [];

      try {
        Map<String, dynamic>? osRow;

        if (serverOsId.isNotEmpty) {
          osRow = await SupabaseManager.client
              .from('os')
              .select('id, servico_solicitado, servico_executado, status_arquivo, deleted')
              .eq('id', serverOsId)
              .maybeSingle();
        } else {
          // fallback por chaves (se existirem no osInfo)
          final empresa = (osInfo['empresa'] ?? '').toString();
          final filial = (osInfo['filial'] ?? '').toString();
          final anomovto = (osInfo['anomovto'] ?? '').toString();
          final nroos = (osInfo['nroos'] ?? '').toString();
          final seqos = (osInfo['seqos'] ?? '').toString();

          if (empresa.isNotEmpty &&
              filial.isNotEmpty &&
              anomovto.isNotEmpty &&
              nroos.isNotEmpty &&
              seqos.isNotEmpty) {
            osRow = await SupabaseManager.client
                .from('os')
                .select('id, servico_solicitado, servico_executado, status_arquivo, deleted')
                .eq('empresa', empresa)
                .eq('filial', filial)
                .eq('anomovto', anomovto)
                .eq('nroos', nroos)
                .eq('seqos', seqos)
                .maybeSingle();

            if (osRow != null) {
              serverOsId = (osRow['id'] ?? '').toString();
            }
          }
        }

        if (osRow != null) {
          servicoSolicitado = (osRow['servico_solicitado'] ?? '').toString();
          servicoExecutado = (osRow['servico_executado'] ?? '').toString();
          statusArquivo = (osRow['status_arquivo'] ?? '').toString();
          deletedServer = (osRow['deleted'] ?? false) == true;
        }

        if (serverOsId.isNotEmpty) {
          final ap = await SupabaseManager.client
              .from('os_apontamentos')
              .select('data, inicio, fim, horas, descricao, tecnico')
              .eq('os_id', serverOsId)
              .order('data', ascending: false)
              .order('inicio', ascending: false);

          apontamentos = (ap as List).cast<Map<String, dynamic>>();
        }
      } catch (_) {
        // segue sem esse bloco
      }

      // ============================
      // BUSCAR NOME CLIENTE
      // ============================
      String clienteNome = '';
      if (clientId.isNotEmpty) {
        try {
          final cli = await SupabaseManager.client
              .from('clientes')
              .select('razao_social')
              .eq('id', clientId)
              .maybeSingle();
          if (cli != null) clienteNome = (cli['razao_social'] ?? '').toString();
        } catch (_) {}
      }

      // ============================
      // SEPARAR MÍDIAS (IMAGEM/VÍDEO/ARQUIVO)
      // ============================

      // Ordena mais novas primeiro (se tiver created_at)
      final sortedMedia = [...mediaFiles]..sort((a, b) {
        final aStr = a['created_at']?.toString() ?? '';
        final bStr = b['created_at']?.toString() ?? '';
        final aDt = DateTime.tryParse(aStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDt = DateTime.tryParse(bStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDt.compareTo(aDt);
      });

      final List<_PdfImage> imagens = [];
      final List<_PdfLink> videos = [];
      final List<_PdfLink> arquivos = [];

      bool _isImageType(dynamic v) {
        final s = (v ?? '').toString().toLowerCase().trim();
        return s == 'image' || s == 'img' || s.contains('image');
      }

      bool _isVideoType(dynamic v) {
        final s = (v ?? '').toString().toLowerCase().trim();
        return s == 'video' || s.contains('video');
      }

      // Para imagens: mais confiável baixar bytes (não depende de URL expirar)
      // Para vídeos/arquivos: usa signed URL (link clicável no PDF)
      for (final f in sortedMedia) {
        final storagePath = (f['storage_path'] ?? '').toString();
        if (storagePath.isEmpty) continue;

        final fileType = f['file_type'];

        final fileName = p.basename(storagePath);

        if (_isImageType(fileType)) {
          try {
            final Uint8List bytes = await SupabaseManager.client.storage
                .from('smi_midias')
                .download(storagePath);

            imagens.add(
              _PdfImage(
                fileName: fileName,
                bytes: bytes,
              ),
            );
          } catch (_) {
            // se falhar a imagem, ignora (PDF segue)
          }
        } else {
          // signed url para clique
          try {
            final url = await SupabaseManager.client.storage
                .from('smi_midias')
                .createSignedUrl(storagePath, 3600);

            final link = _PdfLink(fileName: fileName, url: url);

            if (_isVideoType(fileType)) {
              videos.add(link);
            } else {
              arquivos.add(link);
            }
          } catch (_) {
            // ignora link se falhar
          }
        }
      }

      final int totalImagens = imagens.length;
      final limitedImages = imagens.take(maxImagesInPdf).toList();
      final bool imagesTruncated = totalImagens > maxImagesInPdf;

      // ============================
      // COMPONENTES PDF
      // ============================

      String _arquivoEventoLabel(String v) {
        switch (v.toLowerCase().trim()) {
          case 'inc':
            return 'Incluída (INC)';
          case 'alt':
            return 'Alterada (ALT)';
          case 'exc':
            return 'Excluída (EXC)';
          default:
            return v.isEmpty ? '-' : v;
        }
      }

      pw.Widget header() {
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoImage != null)
              pw.Container(
                width: 55,
                height: 55,
                margin: const pw.EdgeInsets.only(right: 14),
                child: pw.Image(logoImage!, fit: pw.BoxFit.contain),
              ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SMI – Soluções em Manutenção Industrial',
                  style: pw.TextStyle(
                    color: PdfColors.black,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Relatório de Ordem de Serviço',
                  style: pw.TextStyle(
                    color: PdfColors.grey700,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'OS $ano/$osCode',
                  style: pw.TextStyle(
                    color: PdfColors.black,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  _statusLabel(status),
                  style: pw.TextStyle(
                    color: smiGreen,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        );
      }

      pw.Widget footer(pw.Context ctx) {
        final dt = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
        return pw.Row(
          children: [
            pw.Text(
              'Gerado pelo app SMI Arquivos • $dt',
              style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
            pw.Spacer(),
            pw.Text(
              'Página ${ctx.pageNumber}/${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ],
        );
      }

      pw.Widget infoOs() {
        pw.Widget row(String label, String value) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 105,
                  child: pw.Text(
                    label,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: smiDark,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    value.isEmpty ? '-' : value,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
              ],
            ),
          );
        }

        return pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.4),
            borderRadius: pw.BorderRadius.circular(12),
            color: smiLightBg,
          ),
          padding: const pw.EdgeInsets.all(10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              row('Tipo:', tipo),
              row('Setor:', setor),
              row('Status:', _statusLabel(status)),
              row('Ano:', ano),
              row('Código OS:', osCode),
              row('Técnico:', tecnicoNome),
              row('Cliente:', clienteNome),
              if (statusArquivo.isNotEmpty) row('Evento arquivo:', _arquivoEventoLabel(statusArquivo)),
              if (deletedServer) row('Servidor:', 'Marcada como EXCLUÍDA'),
              row('Fotos:', '$totalImagens (PDF: ${limitedImages.length})${imagesTruncated ? ' • LIMITADO' : ''}'),
              row('Vídeos:', videos.isEmpty ? '0' : '${videos.length}'),
              row('Arquivos:', arquivos.isEmpty ? '0' : '${arquivos.length}'),
            ],
          ),
        );
      }

      pw.Widget blocoTexto(String titulo, String conteudo) {
        return pw.Container(
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.4),
          ),
          padding: const pw.EdgeInsets.all(8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                titulo,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: smiDark,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  conteudo.trim().isEmpty ? '—' : conteudo.trim(),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
        );
      }

      pw.Widget resumoTecnico() {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Resumo técnico',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: smiDark,
              ),
            ),
            pw.SizedBox(height: 6),
            blocoTexto('Defeito principal', defeito),
            pw.SizedBox(height: 6),
            blocoTexto('Ação tomada', acao),
            pw.SizedBox(height: 6),
            blocoTexto('Peças trocadas', pecas),
          ],
        );
      }

      // ============================
      // SERVIÇO + APONTAMENTOS
      // ============================

      String _fmtDate(dynamic v) {
        if (v == null) return '-';
        final s = v.toString();
        final dt = DateTime.tryParse(s);
        if (dt == null) return s;
        return DateFormat('dd/MM/yyyy').format(dt);
      }

      String _fmtTime(dynamic v) {
        if (v == null) return '--:--';
        final s = v.toString().trim();
        if (s.isEmpty) return '--:--';
        final parts = s.split(':');
        if (parts.length < 2) return s;
        final hh = parts[0].padLeft(2, '0');
        final mm = parts[1].padLeft(2, '0');
        return '$hh:$mm';
      }

      int? _timeToMinutes(dynamic v) {
        if (v == null) return null;
        final s = v.toString().trim();
        if (s.isEmpty) return null;
        final parts = s.split(':');
        if (parts.length < 2) return null;
        final hh = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        return hh * 60 + mm;
      }

      double? _calcHorasFromTimes(dynamic ini, dynamic fim) {
        final a = _timeToMinutes(ini);
        final b = _timeToMinutes(fim);
        if (a == null || b == null) return null;
        final diff = b - a;
        if (diff <= 0) return null;
        return diff / 60.0;
      }

      pw.Widget apontamentosTable() {
        double total = 0;

        final rows = apontamentos.map((m) {
          final hRaw = m['horas'];
          double? h = (hRaw is num) ? hRaw.toDouble() : double.tryParse(hRaw?.toString() ?? '');
          h ??= _calcHorasFromTimes(m['inicio'], m['fim']);

          if (h != null) total += h;

          final desc = (m['descricao'] ?? '').toString();
          final tec = (m['tecnico'] ?? '').toString();

          return [
            _fmtDate(m['data']),
            _fmtTime(m['inicio']),
            _fmtTime(m['fim']),
            h == null ? '-' : h.toStringAsFixed(2),
            desc.trim().isEmpty ? '—' : desc.trim(),
            tec.trim().isEmpty ? '—' : tec.trim(),
          ];
        }).toList();

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Text(
                  'Apontamento de horas',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: smiDark,
                  ),
                ),
                pw.Spacer(),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: smiLightBg,
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.4),
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                  child: pw.Text(
                    'Total: ${total.toStringAsFixed(2)} h',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: smiDark,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
              columnWidths: {
                0: const pw.FixedColumnWidth(60),
                1: const pw.FixedColumnWidth(42),
                2: const pw.FixedColumnWidth(42),
                3: const pw.FixedColumnWidth(38),
                4: const pw.FlexColumnWidth(3),
                5: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _th('Data'),
                    _th('Início'),
                    _th('Fim'),
                    _th('Horas'),
                    _th('Descrição'),
                    _th('Técnico'),
                  ],
                ),
                ...rows.asMap().entries.map((e) {
                  final idx = e.key;
                  final r = e.value;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: idx.isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      _td(r[0]),
                      _td(r[1]),
                      _td(r[2]),
                      _td(r[3], alignRight: true),
                      _td(r[4]),
                      _td(r[5]),
                    ],
                  );
                }),
              ],
            ),
          ],
        );
      }

      pw.Widget servicoEApontamentos() {
        final hasServico = servicoSolicitado.trim().isNotEmpty || servicoExecutado.trim().isNotEmpty;
        final hasAp = apontamentos.isNotEmpty;

        if (!hasServico && !hasAp) return pw.SizedBox();

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Serviço e horas',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: smiDark,
              ),
            ),
            pw.SizedBox(height: 6),
            if (servicoSolicitado.trim().isNotEmpty) ...[
              blocoTexto('Serviço solicitado (Servidor)', servicoSolicitado),
              pw.SizedBox(height: 6),
            ],
            if (servicoExecutado.trim().isNotEmpty) ...[
              blocoTexto('Serviço executado (Técnico)', servicoExecutado),
              pw.SizedBox(height: 6),
            ],
            if (hasAp) ...[
              apontamentosTable(),
            ] else ...[
              pw.Text(
                'Nenhum apontamento registrado.',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ],
        );
      }

      pw.Widget avisoLimiteImagens() {
        if (!imagesTruncated) return pw.SizedBox();
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.amber50,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(color: PdfColors.amber300, width: 0.6),
          ),
          child: pw.Text(
            'Atenção: existem $totalImagens fotos nesta OS, mas o PDF foi limitado a $maxImagesInPdf fotos para evitar arquivo muito pesado.',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
          ),
        );
      }

      // ============================
      // PÁGINA PRINCIPAL (MultiPage)
      // ============================
      doc.addPage(
        pw.MultiPage(
          pageTheme: pageTheme,
          footer: (ctx) => footer(ctx),
          build: (ctx) => [
            header(),
            pw.SizedBox(height: 16),
            infoOs(),
            avisoLimiteImagens(),
            pw.SizedBox(height: 16),
            resumoTecnico(),
            if (servicoSolicitado.trim().isNotEmpty ||
                servicoExecutado.trim().isNotEmpty ||
                apontamentos.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              servicoEApontamentos(),
            ],
          ],
        ),
      );

      // ============================
      // PÁGINAS DE IMAGENS
      // ============================
      for (final img in limitedImages) {
        doc.addPage(
          pw.Page(
            pageTheme: pageTheme,
            build: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  img.fileName,
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 8),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Image(
                      pw.MemoryImage(img.bytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // ============================
      // PÁGINA DE VÍDEOS
      // ============================
      if (videos.isNotEmpty) {
        doc.addPage(
          pw.MultiPage(
            pageTheme: pageTheme,
            footer: (ctx) => footer(ctx),
            build: (ctx) => [
              pw.Text(
                'Vídeos',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: smiDark,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.grey400, thickness: 0.4),
              pw.SizedBox(height: 8),
              ...videos.map((v) => _linkBlock(v)),
            ],
          ),
        );
      }

      // ============================
      // PÁGINA DE ARQUIVOS (PDF/DOC/ZIP etc)
      // ============================
      if (arquivos.isNotEmpty) {
        doc.addPage(
          pw.MultiPage(
            pageTheme: pageTheme,
            footer: (ctx) => footer(ctx),
            build: (ctx) => [
              pw.Text(
                'Arquivos anexos',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: smiDark,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.grey400, thickness: 0.4),
              pw.SizedBox(height: 8),
              ...arquivos.map((a) => _linkBlock(a)),
            ],
          ),
        );
      }

      // ============================
      // SHARE
      // ============================
      final bytes = await doc.save();
      final filename = 'OS_${ano}_$osCode.pdf';
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar PDF: $e')),
      );
    }
  }

  static pw.Widget _linkBlock(_PdfLink v) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            v.fileName,
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.UrlLink(
            destination: v.url,
            child: pw.Text(
              v.url,
              style: pw.TextStyle(
                fontSize: 8.2,
                color: PdfColors.blue,
                decoration: pw.TextDecoration.underline,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _th(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _td(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Align(
        alignment: alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: const pw.TextStyle(fontSize: 8.5),
          softWrap: true,
        ),
      ),
    );
  }

  static String _statusLabel(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'aberto':
        return 'Aberto';
      case 'em_andamento':
        return 'Em andamento';
      case 'aguardando_cliente':
        return 'Aguardando cliente';
      case 'finalizado':
        return 'Finalizado';
      default:
        return (value == null || value.trim().isEmpty) ? '-' : value!;
    }
  }
}

// =========================
// MODELOS INTERNOS
// =========================

class _PdfImage {
  final String fileName;
  final Uint8List bytes;

  _PdfImage({
    required this.fileName,
    required this.bytes,
  });
}

class _PdfLink {
  final String fileName;
  final String url;

  _PdfLink({
    required this.fileName,
    required this.url,
  });
}
