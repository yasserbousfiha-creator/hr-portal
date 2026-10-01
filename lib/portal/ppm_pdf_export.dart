// PDF export for the portal's PPM reports — requested 2026-10-01 ("اصدرها
// pdf مثل الديسكتوب"). Mirrors hrmanager's generateAndPrintPpmReport in
// shape (title + a table of device/date/type/technician/notes), but uses
// the `printing` package's actual web API (Printing.sharePdf, a direct
// browser download) instead of hrmanager's desktop-only layoutPdf helper,
// which saves to disk and shells out to the OS's default PDF viewer —
// neither of those exist in a browser.
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

pw.Font? _tajawalRegular;
pw.Font? _tajawalBold;

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

String _fmtDateTime(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// `logs`: rows from ppm_maintenance_log. `devicesById`: id -> device row
/// (for the name column — the log table has no device name of its own).
Future<void> exportPpmReportPdf({
  required String title,
  required List<Map<String, dynamic>> logs,
  required Map<String, Map<String, dynamic>> devicesById,
}) async {
  final regular = await _loadRegular();
  final bold = await _loadBold();
  final pdf = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

  final now = DateTime.now();
  final headers = ['الجهاز', 'التاريخ', 'النوع', 'الفني/المسؤول', 'ملاحظات'];
  final rows = logs.map((h) {
    final device = devicesById[h['device_id']];
    return [
      device?['name'] as String? ?? 'جهاز محذوف',
      _fmtDateTime(h['performed_at'] as String?),
      h['type'] == 'طارئة' ? 'طارئة' : 'دورية',
      (h['technician'] as String?) ?? '—',
      (h['notes'] as String?) ?? '',
    ];
  }).toList();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      header: (_) => pw.Column(children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 16, color: PdfColors.indigo800)),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.indigo800, thickness: 1.5),
        pw.SizedBox(height: 10),
      ]),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
          cellStyle: const pw.TextStyle(fontSize: 9.5),
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.centerRight,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        ),
      ],
    ),
  );

  final bytes = await pdf.save();
  await Printing.sharePdf(bytes: bytes, filename: '${title.replaceAll(' ', '_')}.pdf');
}
