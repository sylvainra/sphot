import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Identité graphique commune aux documents financiers SPHOT.
/// Les images sont celles du devis déjà validé ; ne pas les redessiner.
class AdminFinancialPdfBrand {
  const AdminFinancialPdfBrand._(this._title, this._fire);

  final pw.MemoryImage _title;
  final pw.MemoryImage _fire;

  static Future<AdminFinancialPdfBrand> load() async {
    final assets = await Future.wait([
      rootBundle.load('data/icons/title.png'),
      rootBundle.load('data/icons/fire_red_icon.png'),
    ]);
    return AdminFinancialPdfBrand._(
      pw.MemoryImage(assets[0].buffer.asUint8List()),
      pw.MemoryImage(assets[1].buffer.asUint8List()),
    );
  }

  pw.Widget header() => pw.Container(
        height: 53,
        alignment: pw.Alignment.center,
        child: pw.Image(
          _title,
          width: 235,
          height: 49,
          fit: pw.BoxFit.contain,
        ),
      );

  pw.Widget footer(pw.Context context, {required bool specimen}) {
    final grey = PdfColor.fromHex('607D8B');
    final border = PdfColor.fromHex('D9E2EC');
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Center(
          child: pw.Image(_fire, height: 32, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(height: 5),
        pw.Container(height: 0.7, color: border),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Document généré automatiquement par SPHOT',
              style: pw.TextStyle(fontSize: 6.6, color: grey),
            ),
            pw.Text(
              "${specimen ? 'SPÉCIMEN - ' : ''}Version 01 - Page "
              '${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 6.6, color: grey),
            ),
          ],
        ),
      ],
    );
  }
}
