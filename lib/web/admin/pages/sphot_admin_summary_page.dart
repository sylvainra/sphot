// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../../../widgets/adaptive_asset_image.dart';

class SphotAdminSummaryPage extends StatefulWidget {
  final Map<String, dynamic> summary;

  const SphotAdminSummaryPage({
    super.key,
    required this.summary,
  });

  @override
  State<SphotAdminSummaryPage> createState() =>
      _SphotAdminSummaryPageState();
}

class _SphotAdminSummaryPageState extends State<SphotAdminSummaryPage> {
  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _red = Color(0xFFDC2626);
  static const String _rescueStationFlagAsset =
      'data/icons/flag_red_yellow_5x3.svg';

  static const Map<String, String> _sphotLabelIconPaths = {
    '🟦 PAVILLON BLEU': 'data/icons/pavillon_bleu.svg',
    '♿ HANDIPLAGE NIVEAU I': 'data/icons/handiplage1.svg',
    '♿ HANDIPLAGE NIVEAU II': 'data/icons/handiplage2.svg',
    '♿ HANDIPLAGE NIVEAU III': 'data/icons/handiplage3.svg',
    '♿ HANDIPLAGE NIVEAU IV': 'data/icons/handiplage4.svg',
    '🚭 PLAGE SANS TABAC': 'data/icons/plage_sans_tabac.svg',
    'QUALITÉ DES EAUX : EXCELLENTE':
        'data/icons/qualite_eau_excellente.svg',
    'QUALITÉ DES EAUX : BONNE':
        'data/icons/qualite_eau_bonne.svg',
    'QUALITÉ DES EAUX : SUFFISANTE':
        'data/icons/qualite_eau_suffisante.svg',
    'QUALITÉ DES EAUX : INSUFFISANTE':
        'data/icons/qualite_eau_insuffisante.svg',
  };

  static const Map<String, String> _sphotLabelDisplayNames = {
    '🟦 PAVILLON BLEU': 'PAVILLON BLEU',
    '♿ HANDIPLAGE NIVEAU I': 'HANDIPLAGE NIVEAU I',
    '♿ HANDIPLAGE NIVEAU II': 'HANDIPLAGE NIVEAU II',
    '♿ HANDIPLAGE NIVEAU III': 'HANDIPLAGE NIVEAU III',
    '♿ HANDIPLAGE NIVEAU IV': 'HANDIPLAGE NIVEAU IV',
    '🚭 PLAGE SANS TABAC': 'PLAGE SANS TABAC',
  };


  String _clean(dynamic value) => (value ?? '').toString().trim();

  DateTime? _date(dynamic value) {
    if (value is DateTime) return value;

    try {
      final converted = value?.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}

    return null;
  }

  String _formatDate(dynamic value) {
    final date = _date(value);

    if (date == null) {
      return '--/--/----';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _spotName(Map<String, dynamic> spot) {
    for (final key in const [
      'nomSphot',
      'nomSecours',
      'name',
      'nom',
      'title',
    ]) {
      final value = _clean(spot[key]);

      if (value.isNotEmpty) {
        return value;
      }
    }

    return 'SPHOT';
  }

  String _hours(Map<String, dynamic> period) {
    String formatHour(dynamic value) {
      return _clean(value).replaceFirst(':', 'h');
    }

    final start = formatHour(period['startHour']);
    final end = formatHour(period['endHour']);
    final secondStart = formatHour(period['secondStartHour']);
    final secondEnd = formatHour(period['secondEndHour']);

    if (start.isEmpty || end.isEmpty) {
      return '';
    }

    if (secondStart.isNotEmpty && secondEnd.isNotEmpty) {
      return 'DE $start À $end — DE $secondStart À $secondEnd';
    }

    return 'DE $start À $end';
  }

  String _generatedAt() {
    final now = DateTime.now();

    return '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year} à '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  String _labelDisplayName(String value) {
    return _sphotLabelDisplayNames[value] ?? value;
  }

  String? _labelIconPath(String value) {
    return _sphotLabelIconPaths[value];
  }

  Future<void> _printPortrait() async {
    final monitoredSpots = List<Map<String, dynamic>>.from(
      widget.summary['monitoredSpots'] ?? const [],
    );

    final otherSpots = List<Map<String, dynamic>>.from(
      widget.summary['otherSpots'] ?? const [],
    );

    final origin = html.window.location.origin;
    final escape = const HtmlEscape();

    String e(dynamic value) => escape.convert(_clean(value));

    String characteristicRows(Map<String, dynamic> spot) {
      final rawType = _clean(spot['typeSphot']);
      final otherType = _clean(
        spot['autreTypeSphot'] ?? spot['typeSphotAutre'],
      );

      final type = rawType == 'AUTRE' && otherType.isNotEmpty
          ? otherType
          : rawType;

      final equipments = _splitValues(spot['equipement']).toList();
      final otherEquipment = _clean(
        spot['autreEquipement'] ?? spot['equipementAutre'],
      );

      if (otherEquipment.isNotEmpty &&
          !equipments.contains(otherEquipment)) {
        equipments.add(otherEquipment);
      }

      final labels = _splitValues(spot['labelSphot']).toList();
      final otherLabel = _clean(
        spot['autreLabel'] ?? spot['labelSphotAutre'],
      );

      if (otherLabel.isNotEmpty && !labels.contains(otherLabel)) {
        labels.add(otherLabel);
      }

      final webcam = _clean(
        spot['webcamUrl'] ?? spot['urlWebcam'] ?? spot['webcam'],
      );

      final ville = _clean(spot['ville']);
      final departement = _clean(spot['departement']);
      final region = _clean(spot['region']);
      final pays = _clean(spot['pays']);

      final locationParts = [
        ville,
        departement,
        region,
        pays,
      ].where((value) => value.isNotEmpty).toList();

      final normalizedType = type
          .toUpperCase()
          .replaceAll('🚨', '')
          .trim();

      final typeHtml = normalizedType.contains('POSTE DE SECOURS')
          ? '''
            <div class="line">
              <b>Type :</b>
              <span class="rescue-type">
                <img
                  class="rescue-flag"
                  src="$origin/data/icons/flag_red_yellow_5x3.svg"
                  alt=""
                >
                <span>POSTE DE SECOURS</span>
              </span>
            </div>
          '''
          : type.isEmpty
              ? ''
              : '<div class="line"><b>Type :</b> ${e(type)}</div>';

      return '''
        $typeHtml
        ${locationParts.isEmpty ? '' : '<div class="line"><b>Localisation :</b> ${e(locationParts.join(' · '))}</div>'}
        ${equipments.isEmpty ? '' : '<div class="line"><b>Équipements :</b> ${e(equipments.join(' · '))}</div>'}
        ${labels.isEmpty ? '' : '''
          <div class="line label-line">
            <b>Labels :</b>
            <span class="label-list">
              ${labels.map((label) {
                final iconPath = _labelIconPath(label);
                final displayName = _labelDisplayName(label);
                if (iconPath == null) {
                  return '<span class="label-item">${e(displayName)}</span>';
                }
                return '''
                  <span class="label-item">
                    <img class="label-icon" src="$origin/$iconPath" alt="">
                    <span>${e(displayName)}</span>
                  </span>
                ''';
              }).join()}
            </span>
          </div>
        '''}
        ${webcam.isEmpty ? '' : '<div class="line webcam"><b>Webcam :</b> ${e(webcam)}</div>'}
      ''';
    }

    String periodHtml(Map<String, dynamic> period) {
      final name = _clean(period['name']).isEmpty
          ? 'PÉRIODE'
          : _clean(period['name']).toUpperCase();

      final hours = _hours(period);

      return '''
        <div class="period">
          <div>• <b>${e(name)}</b></div>
          <div class="indent">
            DU ${e(_formatDate(period['startDate']))}
            AU ${e(_formatDate(period['endDate']))}
          </div>
          ${hours.isEmpty ? '' : '<div class="indent">${e(hours)}</div>'}
        </div>
      ''';
    }

    String rescuerHtml(Map<String, dynamic> sauveteur) {
      final identity = [
        _clean(sauveteur['prenom']),
        _clean(sauveteur['nom']).toUpperCase(),
      ].where((value) => value.isNotEmpty).join(' ');

      final rawFunctions = sauveteur['fonctions'];

      final functions = rawFunctions is Iterable
          ? rawFunctions
              .map(_clean)
              .where((value) => value.isNotEmpty)
              .join(', ')
          : _clean(rawFunctions);

      final details = <String>[
        if (functions.isNotEmpty) functions,
        if (_clean(sauveteur['age']).isNotEmpty)
          '${_clean(sauveteur['age'])} ans',
        if (_clean(sauveteur['telephone']).isNotEmpty)
          _clean(sauveteur['telephone']),
        if (_clean(sauveteur['email']).isNotEmpty)
          _clean(sauveteur['email']),
        if (_clean(sauveteur['experience']).isNotEmpty)
          'Expérience : ${_clean(sauveteur['experience'])}',
        if (_clean(sauveteur['observations']).isNotEmpty)
          'Observations : ${_clean(sauveteur['observations'])}',
      ];

      return '''
        <div class="rescuer">
          <div class="rescuer-name">${e(identity.isEmpty ? 'Sauveteur' : identity)}</div>
          ${details.map((detail) => '<div>${e(detail)}</div>').join()}
        </div>
      ''';
    }

    String monitoredCard(Map<String, dynamic> entry) {
      final spot = Map<String, dynamic>.from(
        entry['spot'] ?? const {},
      );

      final periods = List<Map<String, dynamic>>.from(
        entry['periods'] ?? const [],
      );

      final sauveteurs = List<Map<String, dynamic>>.from(
        entry['sauveteurs'] ?? const [],
      );

      final idSphot = _clean(
        spot['idSphot'] ?? spot['_docId'],
      );

      final title = idSphot.isEmpty
          ? _spotName(spot)
          : '$idSphot - ${_spotName(spot)}';

      return '''
        <section class="spot-card">
          <h2>${e(title)}</h2>

          <h3>CARACTÉRISTIQUES DU SPHOT</h3>
          ${characteristicRows(spot)}

          <h3>PÉRIODE(S) DE SURVEILLANCE</h3>
          ${periods.isEmpty ? '<div class="muted">Aucune période de surveillance programmée.</div>' : periods.map(periodHtml).join()}

          <h3>SAUVETEURS AFFECTÉS</h3>
          ${sauveteurs.isEmpty ? '<div class="muted">Aucun sauveteur affecté.</div>' : sauveteurs.map(rescuerHtml).join()}
        </section>
      ''';
    }

    String otherCard(Map<String, dynamic> spot) {
      final idSphot = _clean(
        spot['idSphot'] ?? spot['_docId'],
      );

      final title = idSphot.isEmpty
          ? _spotName(spot)
          : '$idSphot - ${_spotName(spot)}';

      return '''
        <section class="spot-card">
          <h2>${e(title)}</h2>
          <h3>CARACTÉRISTIQUES DU SPHOT</h3>
          ${characteristicRows(spot)}
        </section>
      ''';
    }

    final documentHtml = '''
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <title>SPHOT ADMIN – FICHE RÉCAPITULATIVE</title>
  <style>
    @page {
      size: A4 portrait;
      margin: 0;
    }

    * {
      box-sizing: border-box;
    }

    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      max-width: 100%;
      background: #ffffff;
      color: #1E3A8A;
      font-family: Arial, Helvetica, sans-serif;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
      overflow: visible;
    }

    body {
      font-size: 10.5pt;
      padding: 9mm;
    }

    img, div, section, main {
      max-width: 100%;
    }

    .header {
      width: 100%;
      height: 24mm;
      background:
        url("$origin/data/images/map_background.jpg")
        center center / cover no-repeat;
      display: flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
    }

    .header img {
      display: block;
      width: auto;
      height: 16mm;
      max-width: 72%;
      max-height: 16mm;
      object-fit: contain;
    }

    .page-title {
      width: 100%;
      padding: 5mm 2mm 4mm;
      text-align: center;
      color: #1E3A8A;
      font-size: 15pt;
      font-weight: 900;
      letter-spacing: .2mm;
      border-bottom: .25mm solid #dbe4f0;
      overflow-wrap: anywhere;
    }

    .content {
      width: 100%;
      padding-top: 5mm;
    }

    .main-section {
      color: #DC2626;
      font-size: 11.5pt;
      font-weight: 900;
      margin: 0 0 3mm 0;
      letter-spacing: .1mm;
    }

    .spot-card {
      width: 100%;
      max-width: 100%;
      border: .35mm solid #b8c8e3;
      border-radius: 3mm;
      padding: 5mm;
      margin: 0 0 5mm 0;
      overflow-wrap: anywhere;
      word-break: normal;
      break-inside: auto;
      page-break-inside: auto;
    }

    .spot-card h2 {
      margin: 0 0 4mm 0;
      color: #1E3A8A;
      font-size: 14pt;
      font-weight: 900;
    }

    .spot-card h3 {
      margin: 4mm 0 2mm 0;
      color: #DC2626;
      font-size: 10.5pt;
      font-weight: 900;
    }

    .line {
      margin: 0 0 1.5mm 0;
      line-height: 1.25;
      overflow-wrap: anywhere;
    }

    .webcam {
      max-width: 100%;
      word-break: break-all;
      overflow-wrap: anywhere;
    }

    .rescue-type {
      display: inline-flex;
      align-items: center;
      gap: 1mm;
      vertical-align: middle;
    }

    .rescue-flag {
      display: inline-block;
      width: 24px;
      height: 12px;
      max-width: 24px;
      object-fit: fill;
      transform: none;
      margin-right: 0;
      vertical-align: middle;
    }

    .label-line {
      display: flex;
      align-items: flex-start;
      gap: 1.5mm;
    }

    .label-list {
      display: inline-flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 1.5mm 3mm;
    }

    .label-item {
      display: inline-flex;
      align-items: center;
      gap: 1mm;
      white-space: nowrap;
    }

    .label-icon {
      width: 12px;
      height: 12px;
      max-width: 12px;
      object-fit: contain;
      vertical-align: middle;
    }

    .period {
      margin: 0 0 2mm 0;
      line-height: 1.25;
    }

    .indent {
      padding-left: 4mm;
    }

    .rescuer {
      width: 100%;
      max-width: 100%;
      border: .25mm solid #d7dfec;
      border-radius: 2.5mm;
      padding: 3mm;
      margin: 0 0 2mm 0;
      line-height: 1.3;
      overflow-wrap: anywhere;
      break-inside: avoid;
      page-break-inside: avoid;
    }

    .rescuer-name {
      font-weight: 900;
      margin-bottom: 1.5mm;
    }

    .muted {
      color: #60739a;
    }

    .footer {
      border-top: .25mm solid #dbe4f0;
      margin-top: 4mm;
      padding-top: 4mm;
      text-align: center;
      color: #60739a;
      font-size: 8.5pt;
      font-weight: 600;
    }
  </style>
</head>
<body onload="setTimeout(function(){window.print();}, 250);">
  <div class="header">
    <img src="$origin/data/icons/title.png" alt="SPHOT">
  </div>

  <div class="page-title">
    SPHOT ADMIN – FICHE RÉCAPITULATIVE
  </div>

  <main class="content">
    ${monitoredSpots.isEmpty ? '' : '''
      <div class="main-section">SPHOTS SURVEILLÉS</div>
      ${monitoredSpots.map(monitoredCard).join()}
    '''}

    ${otherSpots.isEmpty ? '' : '''
      <div class="main-section">AUTRES SPHOTS</div>
      ${otherSpots.map(otherCard).join()}
    '''}

    ${monitoredSpots.isEmpty && otherSpots.isEmpty ? '<div>Aucun SPHOT enregistré.</div>' : ''}

    <div class="footer">
      Document généré depuis SPHOT ADMIN le ${e(_generatedAt())}.
    </div>
  </main>
</body>
</html>
    ''';

    final blob = html.Blob(
      [documentHtml],
      'text/html;charset=utf-8',
    );

    final url = html.Url.createObjectUrlFromBlob(blob);

    html.window.open(
      url,
      '_blank',
      'noopener,noreferrer',
    );

    Future<void>.delayed(
      const Duration(seconds: 10),
      () => html.Url.revokeObjectUrl(url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monitoredSpots = List<Map<String, dynamic>>.from(
      widget.summary['monitoredSpots'] ?? const [],
    );

    final otherSpots = List<Map<String, dynamic>>.from(
      widget.summary['otherSpots'] ?? const [],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildGlobalSphotHeader(),
          _buildPageTitle(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _printPortrait,
                            icon: const Icon(Icons.print_rounded),
                            label: const Text(
                              'IMPRIMER',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _blue,
                              side: const BorderSide(
                                color: _blue,
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(
                          42,
                          34,
                          42,
                          30,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _blue.withOpacity(0.18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (monitoredSpots.isNotEmpty) ...[
                              _buildMainSectionTitle('SPHOTS SURVEILLÉS'),
                              const SizedBox(height: 12),
                              ...monitoredSpots.map(_buildSpotCard),
                            ],
                            if (otherSpots.isNotEmpty) ...[
                              if (monitoredSpots.isNotEmpty)
                                const SizedBox(height: 6),
                              _buildMainSectionTitle('AUTRES SPHOTS'),
                              const SizedBox(height: 12),
                              ...otherSpots.map(
                                (spot) => _buildOtherSpotCard(spot),
                              ),
                            ],
                            if (monitoredSpots.isEmpty && otherSpots.isEmpty)
                              const Text(
                                'Aucun SPHOT enregistré.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _blue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            const SizedBox(height: 12),
                            Divider(
                              color: _blue.withOpacity(0.18),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Document généré depuis SPHOT ADMIN le '
                              '${_generatedAt()}.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _blue.withOpacity(0.68),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 18),
              child: _buildBackButton(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalSphotHeader() {
    return SizedBox(
      height: 86,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              1.10, 0,    0,    0, -8,
              0,    1.10, 0,    0, -8,
              0,    0,    1.10, 0, -8,
              0,    0,    0,    1,  0,
            ]),
            child: Image.asset(
              'data/images/map_background.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
            ),
          ),
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Image.asset(
                'data/icons/title.png',
                height: 68,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageTitle() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 18,
      ),
      child: const Center(
        child: Text(
          'SPHOT ADMIN – FICHE RÉCAPITULATIVE',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _blue,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: _blue,
          width: 2,
        ),
      ),
      child: IconButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: _blue,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildMainSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _red,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.45,
      ),
    );
  }

  List<String> _splitValues(dynamic value) {
    final raw = _clean(value);

    if (raw.isEmpty) {
      return const [];
    }

    return raw
        .split('|')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != 'AUCUN')
        .toList();
  }

  Widget _buildCharacteristics(Map<String, dynamic> spot) {
    final rawType = _clean(spot['typeSphot']);
    final otherType = _clean(
      spot['autreTypeSphot'] ?? spot['typeSphotAutre'],
    );

    final type = rawType == 'AUTRE' && otherType.isNotEmpty
        ? otherType
        : rawType;

    final equipments = _splitValues(spot['equipement']).toList();
    final otherEquipment = _clean(
      spot['autreEquipement'] ?? spot['equipementAutre'],
    );

    if (otherEquipment.isNotEmpty &&
        !equipments.contains(otherEquipment)) {
      equipments.add(otherEquipment);
    }

    final labels = _splitValues(spot['labelSphot']).toList();
    final otherLabel = _clean(
      spot['autreLabel'] ?? spot['labelSphotAutre'],
    );

    if (otherLabel.isNotEmpty && !labels.contains(otherLabel)) {
      labels.add(otherLabel);
    }

    final webcam = _clean(
      spot['webcamUrl'] ?? spot['urlWebcam'] ?? spot['webcam'],
    );

    final ville = _clean(spot['ville']);
    final departement = _clean(spot['departement']);
    final region = _clean(spot['region']);
    final pays = _clean(spot['pays']);

    final locationParts = [
      ville,
      departement,
      region,
      pays,
    ].where((value) => value.isNotEmpty).toList();

    final hasCharacteristics =
        type.isNotEmpty ||
        equipments.isNotEmpty ||
        labels.isNotEmpty ||
        webcam.isNotEmpty ||
        locationParts.isNotEmpty;

    if (!hasCharacteristics) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildSectionTitle('CARACTÉRISTIQUES DU SPHOT'),
        const SizedBox(height: 8),
        if (type.isNotEmpty)
          _buildTypeCharacteristic(type),
        if (locationParts.isNotEmpty)
          _buildCharacteristicLine(
            'Localisation',
            locationParts.join(' · '),
          ),
        if (equipments.isNotEmpty)
          _buildCharacteristicLine(
            'Équipements',
            equipments.join(' · '),
          ),
        if (labels.isNotEmpty)
          _buildLabelsCharacteristic(labels),
        if (webcam.isNotEmpty)
          _buildCharacteristicLine('Webcam', webcam),
      ],
    );
  }

  Widget _buildLabelsCharacteristic(List<String> labels) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Labels : ',
            style: TextStyle(
              color: _blue,
              fontSize: 11.8,
              fontWeight: FontWeight.w900,
              height: 1.32,
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: labels.map((label) {
                final iconPath = _labelIconPath(label);
                final displayName = _labelDisplayName(label);

                if (iconPath == null) {
                  return Text(
                    displayName,
                    style: const TextStyle(
                      color: _blue,
                      fontSize: 11.8,
                      fontWeight: FontWeight.w600,
                      height: 1.32,
                    ),
                  );
                }

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AdaptiveAssetImage(
                      iconPath,
                      width: 12,
                      height: 12,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 11.8,
                        fontWeight: FontWeight.w600,
                        height: 1.32,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeCharacteristic(String type) {
    final normalized = type
        .toUpperCase()
        .replaceAll('🚨', '')
        .trim();

    final isRescueStation =
        normalized.contains('POSTE DE SECOURS');

    if (!isRescueStation) {
      return _buildCharacteristicLine('Type', type);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Type : ',
            style: TextStyle(
              color: _blue,
              fontSize: 11.8,
              fontWeight: FontWeight.w900,
              height: 1.32,
            ),
          ),
          Transform.scale(
            scaleX: 0.4,
            scaleY: 0.7,
            alignment: Alignment.centerLeft,
            child: AdaptiveAssetImage(
              _rescueStationFlagAsset,
              width: 13,
              height: 20,
              fit: BoxFit.contain,
            ),
          ),
          Flexible(
            child: Transform.translate(
              offset: const Offset(-13, 0),
              child: const Text(
                'POSTE DE SECOURS',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _blue,
                  fontSize: 11.8,
                  fontWeight: FontWeight.w600,
                  height: 1.32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacteristicLine(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: _blue,
            fontSize: 11.8,
            height: 1.32,
          ),
          children: [
            TextSpan(
              text: '$label : ',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherSpotCard(Map<String, dynamic> spot) {
    final idSphot = _clean(
      spot['idSphot'] ?? spot['_docId'],
    );

    final name = _spotName(spot);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _blue.withOpacity(0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            idSphot.isEmpty
                ? name
                : '$idSphot - $name',
            style: const TextStyle(
              color: _blue,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          _buildCharacteristics(spot),
        ],
      ),
    );
  }

  Widget _buildSpotCard(Map<String, dynamic> entry) {
    final spot = Map<String, dynamic>.from(
      entry['spot'] ?? const {},
    );

    final periods = List<Map<String, dynamic>>.from(
      entry['periods'] ?? const [],
    );

    final sauveteurs = List<Map<String, dynamic>>.from(
      entry['sauveteurs'] ?? const [],
    );

    final idSphot = _clean(
      spot['idSphot'] ?? spot['_docId'],
    );

    final name = _spotName(spot);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _blue.withOpacity(0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            idSphot.isEmpty
                ? name
                : '$idSphot - $name',
            style: const TextStyle(
              color: _blue,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          _buildCharacteristics(spot),
          const SizedBox(height: 18),
          _buildSectionTitle(
            'PÉRIODE(S) DE SURVEILLANCE',
          ),
          const SizedBox(height: 8),
          if (periods.isEmpty)
            _buildMutedText(
              'Aucune période de surveillance programmée.',
            )
          else
            ...periods.map(_buildPeriod),
          const SizedBox(height: 16),
          _buildSectionTitle('SAUVETEURS AFFECTÉS'),
          const SizedBox(height: 8),
          if (sauveteurs.isEmpty)
            _buildMutedText(
              'Aucun sauveteur affecté.',
            )
          else
            ...sauveteurs.map(_buildSauveteur),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _red,
        fontSize: 12.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMutedText(String text) {
    return Text(
      text,
      style: TextStyle(
        color: _blue.withOpacity(0.68),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildPeriod(Map<String, dynamic> period) {
    final name = _clean(period['name']).isEmpty
        ? 'PÉRIODE'
        : _clean(period['name']).toUpperCase();

    final hours = _hours(period);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '• $name\n'
        '  DU ${_formatDate(period['startDate'])} '
        'AU ${_formatDate(period['endDate'])}'
        '${hours.isEmpty ? '' : '\n  $hours'}',
        style: const TextStyle(
          color: _blue,
          fontSize: 11.8,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildSauveteur(Map<String, dynamic> sauveteur) {
    final identity = [
      _clean(sauveteur['prenom']),
      _clean(sauveteur['nom']).toUpperCase(),
    ].where((value) => value.isNotEmpty).join(' ');

    final rawFunctions = sauveteur['fonctions'];

    final functions = rawFunctions is Iterable
        ? rawFunctions
            .map(_clean)
            .where((value) => value.isNotEmpty)
            .join(', ')
        : _clean(rawFunctions);

    final details = <String>[
      if (functions.isNotEmpty) functions,
      if (_clean(sauveteur['age']).isNotEmpty)
        '${_clean(sauveteur['age'])} ans',
      if (_clean(sauveteur['telephone']).isNotEmpty)
        _clean(sauveteur['telephone']),
      if (_clean(sauveteur['email']).isNotEmpty)
        _clean(sauveteur['email']),
      if (_clean(sauveteur['experience']).isNotEmpty)
        'Expérience : ${_clean(sauveteur['experience'])}',
      if (_clean(sauveteur['observations']).isNotEmpty)
        'Observations : ${_clean(sauveteur['observations'])}',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _blue.withOpacity(0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            identity.isEmpty ? 'Sauveteur' : identity,
            style: const TextStyle(
              color: _blue,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 5),
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  detail,
                  style: TextStyle(
                    color: _blue.withOpacity(0.76),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
