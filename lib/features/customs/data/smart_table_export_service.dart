import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SmartTableExportService {
  Future<String> exportExcel(SmartTableExportData data) async {
    final excel = Excel.createExcel();
    final sheet = excel['الجدول الذكي'];
    excel.setDefaultSheet('الجدول الذكي');

    sheet.appendRow([TextCellValue(data.title)]);
    sheet.appendRow(
        [TextCellValue('تاريخ التصدير'), TextCellValue(data.generatedAtLabel)]);
    sheet.appendRow([TextCellValue('الفترة'), TextCellValue(data.periodLabel)]);
    sheet.appendRow([TextCellValue('الفلتر'), TextCellValue(data.filterLabel)]);
    sheet.appendRow([TextCellValue('الترتيب'), TextCellValue(data.sortLabel)]);
    sheet.appendRow(
        [TextCellValue('عدد العمليات'), IntCellValue(data.rows.length)]);
    sheet.appendRow(
        [TextCellValue('إجمالي الجمارك'), DoubleCellValue(data.totalCustoms)]);
    sheet.appendRow(
        [TextCellValue('إجمالي السداد'), DoubleCellValue(data.totalPaid)]);
    sheet.appendRow(
        [TextCellValue('الرصيد النهائي'), DoubleCellValue(data.finalBalance)]);
    sheet.appendRow([]);
    sheet.appendRow(
        data.columns.map((column) => TextCellValue(column.label)).toList());

    for (final row in data.rows) {
      sheet.appendRow(
        data.columns.map((column) {
          return TextCellValue(row.cells[column.id] ?? '');
        }).toList(),
      );
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('تعذر إنشاء ملف Excel');
    }

    final path = await _buildExportPath('xlsx');
    await File(path).writeAsBytes(bytes, flush: true);
    await OpenFilex.open(path);
    return path;
  }

  Future<String> exportPdf(SmartTableExportData data) async {
    final bytes = await _buildPdfBytes(data);
    final path = await _buildExportPath('pdf');
    await File(path).writeAsBytes(bytes, flush: true);
    await OpenFilex.open(path);
    return path;
  }

  Future<void> printPdf(SmartTableExportData data) async {
    final bytes = await _buildPdfBytes(data);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<Uint8List> _buildPdfBytes(SmartTableExportData data) async {
    final document = pw.Document();
    final font = await _loadArabicFont();
    final theme = font == null
        ? null
        : pw.ThemeData.withFont(
            base: font,
            bold: font,
          );

    final tableHeaders = data.columns.map((column) => column.label).toList();
    final tableRows = data.rows.map((row) {
      return data.columns.map((column) => row.cells[column.id] ?? '').toList();
    }).toList();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return [
            pw.Text(
              data.title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            _pdfSummary(data),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: tableHeaders,
              data: tableRows,
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerAlignment: pw.Alignment.center,
              cellAlignment: pw.Alignment.center,
              cellPadding: const pw.EdgeInsets.all(3),
            ),
          ];
        },
      ),
    );

    return document.save();
  }

  pw.Widget _pdfSummary(SmartTableExportData data) {
    final items = [
      'تاريخ التصدير: ${data.generatedAtLabel}',
      'الفترة: ${data.periodLabel}',
      'الفلتر: ${data.filterLabel}',
      'الترتيب: ${data.sortLabel}',
      'عدد العمليات: ${data.rows.length}',
      'إجمالي الجمارك: ${data.totalCustoms.toStringAsFixed(2)}',
      'إجمالي السداد: ${data.totalPaid.toStringAsFixed(2)}',
      'الرصيد النهائي: ${data.finalBalance.toStringAsFixed(2)}',
    ];

    return pw.Wrap(
      spacing: 10,
      runSpacing: 6,
      children: items.map((item) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
          ),
          child: pw.Text(item, style: const pw.TextStyle(fontSize: 9)),
        );
      }).toList(),
    );
  }

  Future<pw.Font?> _loadArabicFont() async {
    final candidates = [
      r'C:\Windows\Fonts\tahoma.ttf',
      r'C:\Windows\Fonts\arial.ttf',
      r'C:\Windows\Fonts\segoeui.ttf',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return pw.Font.ttf(ByteData.view(bytes.buffer));
      }
    }

    return null;
  }

  Future<String> _buildExportPath(String extension) async {
    final directory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final timestamp = _fileTimestamp(DateTime.now());
    return p.join(directory.path, 'customs_table_$timestamp.$extension');
  }

  String _fileTimestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${value.year}'
        '${two(value.month)}'
        '${two(value.day)}_'
        '${two(value.hour)}'
        '${two(value.minute)}'
        '${two(value.second)}';
  }
}

class SmartTableExportData {
  const SmartTableExportData({
    required this.title,
    required this.generatedAtLabel,
    required this.periodLabel,
    required this.filterLabel,
    required this.sortLabel,
    required this.totalCustoms,
    required this.totalPaid,
    required this.finalBalance,
    required this.columns,
    required this.rows,
  });

  final String title;
  final String generatedAtLabel;
  final String periodLabel;
  final String filterLabel;
  final String sortLabel;
  final double totalCustoms;
  final double totalPaid;
  final double finalBalance;
  final List<SmartTableExportColumn> columns;
  final List<SmartTableExportRow> rows;
}

class SmartTableExportColumn {
  const SmartTableExportColumn({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class SmartTableExportRow {
  const SmartTableExportRow({required this.cells});

  final Map<String, String> cells;
}
