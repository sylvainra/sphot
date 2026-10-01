import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../pages/sauveteur/widgets/sauveteur_styled_dropdown.dart';
import '../services/operational_alert_sound.dart';

class InstitutionalMainCourantePage extends StatefulWidget {
  const InstitutionalMainCourantePage({
    super.key,
    required this.token,
  });

  final String token;

  @override
  State<InstitutionalMainCourantePage> createState() =>
      _InstitutionalMainCourantePageState();
}

class _InstitutionalMainCourantePageState
    extends State<InstitutionalMainCourantePage> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  static const _purple = Color(0xFF8E24AA);

  final ScrollController _dayScrollController = ScrollController();
  Timer? _operationalStatusTimer;

  bool _loading = true;
  bool _savingPreferences = false;
  String? _errorMessage;
  String? _selectedSpotId;

  late DateTime _selectedDay;

  List<Map<String, dynamic>> _spots = [];
  List<Map<String, dynamic>> _entries = [];
  Map<String, dynamic> _contact = {};
  Map<String, dynamic> _territory = {};
  Map<String, dynamic> _operationalAlert = {};
  String _viewerType = 'institutionnel';
  int? _lastAlertTriggeredAt;
  bool _soundEnabled = true;

  bool _notifyFlagLowered = true;
  bool _notifyIncident = true;
  bool _notifyIntervention = true;

  static const _months = <String>[
    'JANVIER',
    'FÉVRIER',
    'MARS',
    'AVRIL',
    'MAI',
    'JUIN',
    'JUILLET',
    'AOÛT',
    'SEPTEMBRE',
    'OCTOBRE',
    'NOVEMBRE',
    'DÉCEMBRE',
  ];

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = _today;
    _load();
    _operationalStatusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshOperationalStatus(),
    );
  }

  @override
  void dispose() {
    _operationalStatusTimer?.cancel();
    _dayScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.token.trim().isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = 'Lien institutionnel incomplet ou expiré.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'getInstitutionalMainCourante',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': widget.token,
          'spotId': _selectedSpotId,
          'dayStartMillis': DateTime(
            _selectedDay.year,
            _selectedDay.month,
            _selectedDay.day,
          ).millisecondsSinceEpoch,
          'dayEndMillis': DateTime(
            _selectedDay.year,
            _selectedDay.month,
            _selectedDay.day + 1,
          ).millisecondsSinceEpoch,
        }),
      );

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _loading = false;
          _errorMessage =
              'Cet accès institutionnel n’est plus disponible.';
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        setState(() {
          _loading = false;
          _errorMessage =
              'Impossible de charger la MAIN COURANTE institutionnelle.';
        });
        return;
      }

      final spots = decoded['spots'] is List
          ? (decoded['spots'] as List)
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .toList()
          : <Map<String, dynamic>>[];
      final entries = decoded['entries'] is List
          ? (decoded['entries'] as List)
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .toList()
          : <Map<String, dynamic>>[];
      final preferences = decoded['notificationPreferences'] is Map
          ? Map<String, dynamic>.from(
              decoded['notificationPreferences'] as Map,
            )
          : <String, dynamic>{};
      final operationalAlert = decoded['operationalAlert'] is Map
          ? Map<String, dynamic>.from(
              decoded['operationalAlert'] as Map,
            )
          : <String, dynamic>{};
      final triggeredAt = operationalAlert['triggeredAt'] is num
          ? (operationalAlert['triggeredAt'] as num).toInt()
          : null;

      setState(() {
        _spots = spots;
        _entries = entries;
        _selectedSpotId =
            (decoded['selectedSpotId'] ?? '').toString().trim().isEmpty
                ? null
                : decoded['selectedSpotId'].toString().trim();
        _contact = decoded['contact'] is Map
            ? Map<String, dynamic>.from(decoded['contact'] as Map)
            : <String, dynamic>{};
        _territory = decoded['territory'] is Map
            ? Map<String, dynamic>.from(decoded['territory'] as Map)
            : <String, dynamic>{};
        _operationalAlert = operationalAlert;
        _viewerType =
            (decoded['viewerType'] ?? 'institutionnel').toString().toLowerCase();
        if (_lastAlertTriggeredAt == null &&
            operationalAlert['active'] == true &&
            triggeredAt != null) {
          _lastAlertTriggeredAt = triggeredAt;
        }
        _notifyFlagLowered = preferences['flagLowered'] != false;
        _notifyIncident = preferences['incident'] != false;
        _notifyIntervention = preferences['intervention'] != false;
        _loading = false;
      });

      _scrollSelectedDayIntoView();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            'Impossible de joindre le service MAIN COURANTE actuellement.';
      });
    }
  }


  Future<void> _refreshOperationalStatus() async {
    if (!mounted || widget.token.trim().isEmpty || _selectedSpotId == null) {
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'getInstitutionalMainCourante',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': widget.token,
          'spotId': _selectedSpotId,
          'statusOnly': true,
        }),
      );

      if (!mounted || response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        return;
      }

      final nextAlert = decoded['operationalAlert'] is Map
          ? Map<String, dynamic>.from(
              decoded['operationalAlert'] as Map,
            )
          : <String, dynamic>{};
      final triggeredAt = nextAlert['triggeredAt'] is num
          ? (nextAlert['triggeredAt'] as num).toInt()
          : null;
      final isNewActiveAlert =
          nextAlert['active'] == true &&
          triggeredAt != null &&
          triggeredAt != _lastAlertTriggeredAt;

      if (triggeredAt != null && nextAlert['active'] == true) {
        _lastAlertTriggeredAt = triggeredAt;
      }

      setState(() {
        _operationalAlert = nextAlert;
      });

      if (isNewActiveAlert && _soundEnabled) {
        await playOperationalFogHorn();
      }

      if (isNewActiveAlert && mounted) {
        final message = (nextAlert['message'] ?? 'Drapeau affalé').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _red,
            duration: const Duration(seconds: 6),
            content: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        );
      }
    } catch (_) {
      // Le polling silencieux ne doit jamais interrompre la consultation.
    }
  }

  Future<void> _savePreferences() async {
    if (_savingPreferences) return;

    setState(() => _savingPreferences = true);

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'updateInstitutionalMainCourantePreferences',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': widget.token,
          'flagLowered': _notifyFlagLowered,
          'incident': _notifyIncident,
          'intervention': _notifyIntervention,
        }),
      );

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _errorMessage =
              'Les préférences n’ont pas pu être enregistrées.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Les préférences n’ont pas pu être enregistrées.';
      });
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  Future<void> _selectDay(DateTime day) async {
    if (day.isAfter(_today)) return;

    setState(() {
      _selectedDay = DateTime(day.year, day.month, day.day);
    });

    _scrollSelectedDayIntoView();
    await _load();
  }

  void _scrollSelectedDayIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_dayScrollController.hasClients) return;

      final desiredOffset = ((_selectedDay.day - 3) * 48.0)
          .clamp(
            0.0,
            _dayScrollController.position.maxScrollExtent,
          )
          .toDouble();

      _dayScrollController.animateTo(
        desiredOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _formatDate(dynamic rawMillis) {
    final millis = rawMillis is num ? rawMillis.toInt() : null;
    if (millis == null) return 'Date non renseignée';

    final date = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/${date.year} — $hour:$minute';
  }

  Widget _dayTabs() {
    final today = _today;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue, width: 1.3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_months[today.month - 1]} ${today.year}',
            style: const TextStyle(
              color: _blue,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView.builder(
              controller: _dayScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: daysInMonth,
              itemBuilder: (context, index) {
                final date = DateTime(today.year, today.month, index + 1);
                final selected =
                    _selectedDay.year == date.year &&
                    _selectedDay.month == date.month &&
                    _selectedDay.day == date.day;
                final future = date.isAfter(today);

                return Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: future ? null : () => _selectDay(date),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? _purple
                            : future
                                ? Colors.black.withOpacity(0.04)
                                : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? _purple
                              : _blue.withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : future
                                  ? Colors.black26
                                  : _blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> entry) {
    final source = (entry['source'] ?? '').toString();
    final automatic = source.startsWith('automatic_');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (entry['type'] ?? 'Observation')
                      .toString()
                      .toUpperCase(),
                  style: const TextStyle(
                    color: _purple,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (automatic)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'AUTOMATIQUE',
                    style: TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _formatDate(entry['occurredAt']),
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            (entry['description'] ?? '').toString(),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if ((entry['actionTaken'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Suite donnée : ${(entry['actionTaken'] ?? '').toString()}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }


  Widget _operationalAlertBanner() {
    if (_operationalAlert['active'] != true) {
      return const SizedBox.shrink();
    }

    final message = (_operationalAlert['message'] ?? '')
        .toString()
        .trim();
    final triggeredAt = _operationalAlert['triggeredAt'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _red, width: 1.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.crisis_alert_rounded, color: _red, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ÉVÉNEMENT OPÉRATIONNEL EN COURS',
                  style: TextStyle(
                    color: _red,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            message.isEmpty ? 'Drapeau du poste de secours affalé' : message,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          if (triggeredAt is num) ...[
            const SizedBox(height: 3),
            Text(
              'Déclenché le ${_formatDate(triggeredAt)}',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 7),
          const Text(
            'Les informations complémentaires seront renseignées dans la '
            'MAIN COURANTE dès que la situation opérationnelle le permettra.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 10.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _preferencesCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.93),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications_active_outlined, color: _blue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MES NOTIFICATIONS',
                  style: TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'LECTURE SEULE',
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Affalage du drapeau'),
            value: _notifyFlagLowered,
            onChanged: (value) {
              setState(() => _notifyFlagLowered = value);
              _savePreferences();
            },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Corne de brume sur cette page'),
            subtitle: const Text(
              'Le navigateur doit autoriser la lecture du son.',
              style: TextStyle(fontSize: 10.5),
            ),
            value: _soundEnabled,
            onChanged: (value) async {
              setState(() => _soundEnabled = value);
              if (value) {
                await playOperationalFogHorn();
              }
            },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Incident'),
            value: _notifyIncident,
            onChanged: (value) {
              setState(() => _notifyIncident = value);
              _savePreferences();
            },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Intervention'),
            value: _notifyIntervention,
            onChanged: (value) {
              setState(() => _notifyIntervention = value);
              _savePreferences();
            },
          ),
          if (_savingPreferences)
            const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = [
      (_contact['civilite'] ?? '').toString().trim(),
      (_contact['prenom'] ?? '').toString().trim(),
      (_contact['nom'] ?? '').toString().trim(),
    ].where((value) => value.isNotEmpty).join(' ');

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: 94,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: _dayTabs(),
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null && _spots.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _red,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      children: [
                        Image.asset(
                          'data/icons/title.png',
                          height: 52,
                          fit: BoxFit.contain,
                        ),
                        Text(
                          _viewerType == 'admin'
                              ? 'MAIN COURANTE — ACCÈS ADMIN'
                              : 'MAIN COURANTE — ACCÈS INSTITUTIONNEL',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _red,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (identity.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            identity,
                            style: const TextStyle(
                              color: _blue,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        if ((_territory['organisation'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          Text(
                            (_territory['organisation'] ?? '').toString(),
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        const SizedBox(height: 10),
                        _operationalAlertBanner(),
                        if (_operationalAlert['active'] == true)
                          const SizedBox(height: 10),
                        _preferencesCard(),
                        const SizedBox(height: 10),
                        if (_spots.isNotEmpty)
                          SauveteurStyledDropdown(
                            labelText: 'Poste de secours',
                            value: _selectedSpotId,
                            options: _spots
                                .map(
                                  (spot) => SauveteurDropdownOption(
                                    value: (spot['id'] ?? '').toString(),
                                    label: (spot['label'] ?? '').toString(),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) async {
                              setState(() => _selectedSpotId = value);
                              await _load();
                            },
                          ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: _blue, width: 1.5),
                            ),
                            child: ListView(
                              children: [
                                if (_errorMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      _errorMessage!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: _red,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                if (_entries.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                      'Aucun fait enregistré pour cette journée.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  )
                                else
                                  ..._entries.map(_entryCard),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
