import 'dart:typed_data';

import 'admin_quote_pdf_download_stub.dart'
    if (dart.library.html) 'admin_quote_pdf_download_web.dart' as platform;

/// Téléchargement local : aucune écriture Firebase ni email.
void downloadAdminQuoteSpecimen(Uint8List bytes, String filename) {
  platform.downloadPdf(bytes, filename);
}


/// Export comptable préparatoire destiné au Super Admin.
void downloadSuperAdminFinancialCsv(Uint8List bytes, String filename) {
  platform.downloadCsv(bytes, filename);
}
