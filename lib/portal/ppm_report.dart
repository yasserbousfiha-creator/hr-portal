import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'portal_client.dart';

class PickedPpmReport {
  final String name;
  final Uint8List bytes;
  final String contentType;

  const PickedPpmReport({required this.name, required this.bytes, required this.contentType});
}

/// The technician's written maintenance report (JPEG or PNG), optional per visit.
Future<PickedPpmReport?> pickPpmReport() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png'],
    withData: true,
    allowMultiple: false,
  );
  final file = result?.files.single;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  final isPng = (file.extension ?? '').toLowerCase() == 'png';
  return PickedPpmReport(
    name: file.name,
    bytes: bytes,
    contentType: isPng ? 'image/png' : 'image/jpeg',
  );
}

/// Uploads straight to R2 through a short-lived presigned URL from the
/// `ppm-report` function. Returns the storage key to save on the log row.
Future<String> uploadPpmReport({required String logId, required PickedPpmReport report}) async {
  final ext = report.contentType == 'image/png' ? 'png' : 'jpg';
  final key = 'reports/$logId.$ext';
  final res = await portalClient.functions.invoke(
    'ppm-report',
    body: {
      'action': 'createReportUploadUrl',
      'payload': {'key': key, 'contentType': report.contentType},
    },
  );
  final url = ((res.data as Map)['data'] as Map)['url'] as String;
  final put = await http.put(
    Uri.parse(url),
    headers: {'Content-Type': report.contentType},
    body: report.bytes,
  );
  if (put.statusCode != 200) {
    throw Exception('report upload failed: ${put.statusCode}');
  }
  return key;
}

Future<String> ppmReportViewUrl(String key) async {
  final res = await portalClient.functions.invoke(
    'ppm-report',
    body: {
      'action': 'createReportViewUrl',
      'payload': {'key': key},
    },
  );
  return ((res.data as Map)['data'] as Map)['url'] as String;
}
