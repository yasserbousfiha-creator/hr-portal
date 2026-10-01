// PDF export for the portal's PPM reports — requested 2026-10-01 ("اصدرها
// pdf مثل الديسكتوب... بنفس اللوغو... بالعربية يكون من اليمين لليسار،
// اسم الجهاز أول شيء"). Mirrors hrmanager's generateAndPrintPpmReport as
// closely as practical: same logo, same RTL table approach, same column
// order — but uses the `printing` package's actual web API
// (Printing.sharePdf, a browser download) instead of hrmanager's
// desktop-only layoutPdf, which saves to disk and shells out to the OS's
// PDF viewer — neither exists in a browser.
//
// IMPORTANT: `pw.TableHelper.fromTextArray` (tried first) does NOT respect
// the ambient RTL `textDirection` the way a hand-built `pw.Table`/`pw.Row`
// does in this package — it always renders columns left-to-right
// regardless of document direction, which put "الجهاز" last instead of
// first. hrmanager's own PDF code works around this the same way: build
// the table manually with pw.Table/pw.TableRow so column order follows
// the list order, authored first-to-last in reading order (device name
// first = rightmost in RTL, since pw.Row/pw.Table DO respect
// Directionality for row/column placement — just not fromTextArray).
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
}) async {
  final regular = await _loadRegular();
  final bold = await _loadBold();
  final logo = await _loadLogo();
  final pdf = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

  final now = DateTime.now();

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
      build: (_) => [
        if (logs.isEmpty)
          pw.Text('لا يوجد سجل صيانة بعد', style: const pw.TextStyle(fontSize: 11))
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey200),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(1.6),
              2: pw.FlexColumnWidth(1.1),
              3: pw.FlexColumnWidth(1.6),
              4: pw.FlexColumnWidth(2.3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.indigo700),
                children: [
                  _cell(bold, 'الجهاز', hdr: true),
                  _cell(bold, 'التاريخ', hdr: true),
                  _cell(bold, 'النوع', hdr: true),
                  _cell(bold, 'الفني/المسؤول', hdr: true),
                  _cell(bold, 'ملاحظات', hdr: true),
                ],
              ),
              ...logs.asMap().entries.map((entry) {
                final i = entry.key;
                final h = entry.value;
                final device = devicesById[h['device_id']];
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: i.isEven ? const PdfColor.fromInt(0xFFF8FAFC) : PdfColors.white,
                  ),
                  children: [
                    _cell(bold, device?['name'] as String? ?? 'جهاز محذوف'),
                    _cell(bold, _fmtDateTime(h['performed_at'] as String?)),
                    _cell(bold, h['type'] == 'طارئة' ? 'طارئة' : 'دورية'),
                    _cell(bold, (h['technician'] as String?) ?? '—'),
                    _cell(bold, (h['notes'] as String?)?.isNotEmpty == true ? h['notes'] as String : '—'),
                  ],
                );
              }),
            ],
          ),
      ],
    ),
  );

  final bytes = await pdf.save();
  await Printing.sharePdf(bytes: bytes, filename: '${title.replaceAll(' ', '_')}.pdf');
}
