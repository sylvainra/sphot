// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';

class SphotAdminSummaryPage extends StatelessWidget {
  final Map<String, dynamic> summary;

  const SphotAdminSummaryPage({super.key, required this.summary});

  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  String _text(dynamic value) => (value ?? '').toString().trim();

  DateTime? _date(dynamic value) {
    if (value is DateTime) return value;
    try {
      final dynamic converted = value?.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}
    return null;
  }

  String _formatDate(dynamic value) {
    final date = _date(value);
    if (date == null) return '--/--/----';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _generatedAt() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} à ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _spotName(Map<String, dynamic> spot) {
    for (final key in const ['nomSphot', 'nomSecours', 'name', 'nom', 'title']) {
      final value = _text(spot[key]);
      if (value.isNotEmpty) return value;
    }
    return 'SPHOT';
  }

  String _listText(dynamic value) {
    if (value is Iterable) {
      return value.map(_text).where((item) => item.isNotEmpty).join(', ');
    }
    return _text(value);
  }

  String _hours(Map<String, dynamic> period) {
    String h(dynamic value) => _text(value).replaceFirst(':', 'h');
    final start = h(period['startHour']);
    final end = h(period['endHour']);
    final secondStart = h(period['secondStartHour']);
    final secondEnd = h(period['secondEndHour']);
    if (start.isEmpty || end.isEmpty) return '';
    if (secondStart.isNotEmpty && secondEnd.isNotEmpty) {
      return 'DE $start À $end — DE $secondStart À $secondEnd';
    }
    return 'DE $start À $end';
  }

  @override
  Widget build(BuildContext context) {
    final spots = List<Map<String, dynamic>>.from(
      summary['monitoredSpots'] ?? const [],
    );
    final periodCount = summary['periodCount'] ??
        spots.fold<int>(
          0,
          (count, entry) =>
              count + List<Map<String, dynamic>>.from(entry['periods'] ?? const []).length,
        );
    final sauveteurCount = summary['sauveteurCount'] ??
        spots.fold<int>(
          0,
          (count, entry) =>
              count + List<Map<String, dynamic>>.from(entry['sauveteurs'] ?? const []).length,
        );

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _sphotHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 930),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('RETOUR'),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: html.window.print,
                            icon: const Icon(Icons.print_rounded),
                            label: const Text('IMPRIMER'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: adminColor,
                              side: const BorderSide(color: adminColor, width: 1.4),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.fromLTRB(48, 42, 48, 34),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: adminColor.withOpacity(0.18)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'SPHOT ADMIN – FICHE RÉCAPITULATIVE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: adminColor,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Row(
                              children: [
                                Expanded(child: _counter(Icons.shield_outlined, '${spots.length}', 'SPHOTS surveillés')),
                                const SizedBox(width: 12),
                                Expanded(child: _counter(Icons.calendar_month_outlined, '$periodCount', 'périodes')),
                                const SizedBox(width: 12),
                                Expanded(child: _counter(Icons.groups_2_outlined, '$sauveteurCount', 'sauveteurs')),
                              ],
                            ),
                            const SizedBox(height: 28),
                            if (spots.isEmpty)
                              const Text(
                                'Aucun SPHOT surveillé enregistré.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: adminColor, fontWeight: FontWeight.w700),
                              )
                            else
                              ...spots.map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: _spotCard(entry),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Divider(color: adminColor.withOpacity(0.18)),
                            const SizedBox(height: 14),
                            Text(
                              'Document généré depuis SPHOT ADMIN le ${_generatedAt()}.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: adminColor.withOpacity(0.68),
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
        ],
      ),
    );
  }

  Widget _sphotHeader() {
    return Container(
      height: 104,
      width: double.infinity,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('data/images/map_background.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'S P H',
              style: TextStyle(
                color: Color(0xFFFF8A00),
                fontSize: 43,
                fontWeight: FontWeight.w900,
                letterSpacing: 5.5,
              ),
            ),
            const SizedBox(width: 9),
            Image.asset('data/icons/fire_red_icon.png', width: 48, height: 48),
            const SizedBox(width: 9),
            const Text(
              'T',
              style: TextStyle(
                color: Color(0xFFFF8A00),
                fontSize: 43,
                fontWeight: FontWeight.w900,
                letterSpacing: 5.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counter(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: adminColor.withOpacity(0.045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: adminColor.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: adminColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$value $label',
              style: const TextStyle(color: adminColor, fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _spotCard(Map<String, dynamic> entry) {
    final spot = Map<String, dynamic>.from(entry['spot'] ?? const {});
    final periods = List<Map<String, dynamic>>.from(entry['periods'] ?? const []);
    final sauveteurs = List<Map<String, dynamic>>.from(entry['sauveteurs'] ?? const []);
    final id = _text(spot['idSphot'] ?? spot['_docId']);
    final name = _spotName(spot);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: adminColor.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            id.isEmpty ? name : '$id - $name',
            style: const TextStyle(color: adminColor, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          _sectionTitle('PÉRIODES DE SURVEILLANCE'),
          const SizedBox(height: 8),
          if (periods.isEmpty)
            _muted('Aucune période de surveillance programmée.')
          else
            ...periods.map(_periodRow),
          const SizedBox(height: 18),
          _sectionTitle('SAUVETEURS AFFECTÉS'),
          const SizedBox(height: 8),
          if (sauveteurs.isEmpty)
            _muted('Aucun sauveteur affecté.')
          else
            ...sauveteurs.map((sauveteur) => _sauveteurCard(sauveteur, periods)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(color: redColor, fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      );

  Widget _muted(String text) => Text(
        text,
        style: TextStyle(color: adminColor.withOpacity(0.66), fontSize: 12, fontWeight: FontWeight.w600),
      );

  Widget _periodRow(Map<String, dynamic> period) {
    final name = _text(period['name']).isEmpty ? 'PÉRIODE' : _text(period['name']).toUpperCase();
    final hours = _hours(period);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '• $name\n   DU ${_formatDate(period['startDate'])} AU ${_formatDate(period['endDate'])}${hours.isEmpty ? '' : '\n   $hours'}',
        style: const TextStyle(color: adminColor, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.35),
      ),
    );
  }

  Widget _sauveteurCard(Map<String, dynamic> sauveteur, List<Map<String, dynamic>> periods) {
    final prenom = _text(sauveteur['prenom']);
    final nom = _text(sauveteur['nom']).toUpperCase();
    final identity = [prenom, nom].where((value) => value.isNotEmpty).join(' ');
    final functions = _listText(sauveteur['fonctions']);
    final phone = _text(sauveteur['telephone']);
    final email = _text(sauveteur['email']);
    final age = _text(sauveteur['age']);
    final experience = _text(sauveteur['experience']);
    final observations = _text(sauveteur['observations']);
    final rawPeriodIds = sauveteur['periodesSurveillance'];
    final periodIds = rawPeriodIds is Iterable
        ? rawPeriodIds.map(_text).where((value) => value.isNotEmpty).toSet()
        : <String>{};
    final assignedPeriods = periods
        .where((period) => periodIds.contains(_text(period['_docId'])))
        .map((period) => _text(period['name']).toUpperCase())
        .where((value) => value.isNotEmpty)
        .toList();
    final details = <String>[
      if (functions.isNotEmpty) functions,
      if (age.isNotEmpty) '$age ans',
      if (phone.isNotEmpty) phone,
      if (email.isNotEmpty) email,
      if (experience.isNotEmpty) 'Expérience : $experience',
      if (assignedPeriods.isNotEmpty) 'Périodes : ${assignedPeriods.join(', ')}',
      if (observations.isNotEmpty) 'Observations : $observations',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: adminColor.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            identity.isEmpty ? 'Sauveteur' : identity,
            style: const TextStyle(color: adminColor, fontSize: 12.5, fontWeight: FontWeight.w900),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 5),
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  detail,
                  style: TextStyle(color: adminColor.withOpacity(0.76), fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
