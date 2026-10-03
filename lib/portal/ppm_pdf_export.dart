// PDF export for the portal's PPM reports, laid out like hrmanager's desktop
// report: same logo, same RTL table approach, and each visit that has report
// images gets its own A4 page (device details on top, the image below). Visits
// without images are grouped into one continuous table. Uses the `printing`
// package's browser download (Printing.sharePdf).
//
// pw.Table lays its children out left-to-right as authored regardless of text
// direction, so cells are listed last-to-first (device name last = rightmost).
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'ppm_report.dart';

enum PpmPdfAttachments { all, withAttachments, withoutAttachments }

pw.Font? _tajawalRegular;
pw.Font? _tajawalBold;
pw.MemoryImage? _logoImage;

Future<pw.Font> _loadRegular() async {
  final cached = _tajawalRegular;
  if (cached != null) return cached;
  final data = await rootBundle.load('assets/fonts/Tajawal-Regular.ttf');
  return _tajawalRegular = pw.Font.ttf(data);
}

Future<pw.Font> _loadBold() async {
  final cached = _tajawalBold;
  if (cached != null) return cached;
  final data = await rootBundle.load('assets/fonts/Tajawal-Bold.ttf');
  return _tajawalBold = pw.Font.ttf(data);
}

Future<pw.MemoryImage?> _loadLogo() async {
  final cached = _logoImage;
  if (cached != null) return cached;
  try {
    final data = await rootBundle.load('assets/images/logo.png');
    return _logoImage = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

String _fmtDateTime(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

List<String> _reportKeysOf(Map<String, dynamic> h) {
  final keys = <String>{
    ...((h['report_keys'] as List?) ?? const []).map((k) => k.toString()),
    if (_nonEmpty(h['report_key']) != null) h['report_key'] as String,
  };
  return keys.where((k) => k.isNotEmpty).toList();
}

pw.Widget _cell(pw.Font bold, String text, {bool hdr = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: hdr
            ? pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white)
            : const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
      ),
    );

/// `logs`: rows from ppm_maintenance_log. `devicesById`: id -> device row
/// (for the name column — the log table has no device name of its own).
Future<void> exportPpmReportPdf({
  required String title,
  required List<Map<String, dynamic>> logs,
  required Map<String, Map<String, dynamic>> devicesById,
  PpmPdfAttachments attachments = PpmPdfAttachments.all,
}) async {
  final entries = switch (attachments) {
    PpmPdfAttachments.all => logs,
    PpmPdfAttachments.withAttachments => logs.where((h) => _reportKeysOf(h).isNotEmpty).toList(),
    PpmPdfAttachments.withoutAttachments => logs.where((h) => _reportKeysOf(h).isEmpty).toList(),
  };

  final regular = await _loadRegular();
  final bold = await _loadBold();
  final logo = await _loadLogo();

  final imagesByLog = <Object?, List<pw.MemoryImage>>{};
  for (final h in entries) {
    for (final key in _reportKeysOf(h)) {
      final resp = await http.get(Uri.parse(await ppmReportViewUrl(key)));
      if (resp.statusCode == 200) {
        imagesByLog.putIfAbsent(h['id'], () => []).add(pw.MemoryImage(resp.bodyBytes));
      }
    }
  }

  final pdf = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
  final now = DateTime.now();


  pw.Widget tableOf(List<Map<String, dynamic>> rows) => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey200),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.3),
          1: pw.FlexColumnWidth(1.6),
          2: pw.FlexColumnWidth(1.1),
          3: pw.FlexColumnWidth(1.6),
          4: pw.FlexColumnWidth(2.2),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.indigo700),
            children: [
              _cell(bold, 'ملاحظات', hdr: true),
              _cell(bold, 'الفني/المسؤول', hdr: true),
              _cell(bold, 'النوع', hdr: true),
              _cell(bold, 'التاريخ', hdr: true),
              _cell(bold, 'الجهاز', hdr: true),
            ],
          ),
          ...rows.asMap().entries.map((entry) {
            final h = entry.value;
            final device = devicesById[h['device_id']];
            return pw.TableRow(
              decoration: pw.BoxDecoration(
                color: entry.key.isEven ? const PdfColor.fromInt(0xFFF8FAFC) : PdfColors.white,
              ),
              children: [
                _cell(bold, (h['notes'] as String?)?.isNotEmpty == true ? h['notes'] as String : '—'),
                _cell(bold, (h['technician'] as String?) ?? '—'),
                _cell(bold, h['type'] == 'طارئة' ? 'طارئة' : 'دورية'),
                _cell(bold, _fmtDateTime(h['performed_at'] as String?)),
                _cell(bold, device?['name'] as String? ?? 'جهاز محذوف'),
              ],
            );
          }),
        ],
      );

  pw.Widget visitFrame(Map<String, dynamic> h, List<pw.MemoryImage> images) {
    final imageHeight = images.length > 1 ? 300.0 : 480.0;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.indigo300, width: 1.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          tableOf([h]),
          pw.SizedBox(height: 12),
          for (final img in images) ...[
            pw.Center(child: pw.Image(img, height: imageHeight, fit: pw.BoxFit.contain)),
            pw.SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  final body = <pw.Widget>[];
  if (entries.isEmpty) {
    body.add(pw.Text('لا يوجد سجل صيانة بعد', style: const pw.TextStyle(fontSize: 11)));
  } else {
    final pending = <Map<String, dynamic>>[];
    var pagesAdded = false;
    for (final h in entries) {
      final images = imagesByLog[h['id']] ?? const <pw.MemoryImage>[];
      if (images.isEmpty) {
        pending.add(h);
        continue;
      }
      body.add(pw.NewPage());
      body.add(visitFrame(h, images));
      pagesAdded = true;
    }
    if (pending.isNotEmpty) {
      if (pagesAdded) body.add(pw.NewPage());
      body.add(tableOf(List.of(pending)));
    }
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      header: (_) => pw.Column(children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 14, color: PdfColors.indigo800)),
                pw.Text(
                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
            if (logo != null) pw.Image(logo, height: 36),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: PdfColors.indigo800, thickness: 2),
        pw.SizedBox(height: 10),
      ]),
      build: (_) => body,
    ),
  );

  final bytes = await pdf.save();
  await Printing.sharePdf(bytes: bytes, filename: '${title.replaceAll(' ', '_')}.pdf');
}
