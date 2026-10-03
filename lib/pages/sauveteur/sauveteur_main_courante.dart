import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'widgets/sauveteur_styled_dropdown.dart';

class SauveteurMainCourantePage extends StatefulWidget {
  final Color profileColor;
  final String userRole;
  final String territoireId;
  final String login;
  final String sphotMode;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final String? initialSpotId;
  final bool canManageRestrictedOperationalData;

  const SauveteurMainCourantePage({
    super.key,
    required this.profileColor,
    required this.userRole,
    required this.territoireId,
    required this.login,
    required this.sphotMode,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.initialSpotId,
    required this.canManageRestrictedOperationalData,
  });

  @override
  State<SauveteurMainCourantePage> createState() =>
      _SauveteurMainCourantePageState();
}

class _SauveteurMainCourantePageState
    extends State<SauveteurMainCourantePage> {
  final _descriptionController = TextEditingController();
  final _victimNameController = TextEditingController();
  final _victimFirstNameController = TextEditingController();
  final _victimAgeController = TextEditingController();
  final _victimBirthDateController = TextEditingController();
  final _victimResidenceController = TextEditingController();
  final _victimPhoneController = TextEditingController();
  final _dayScrollController = ScrollController();
  late stt.SpeechToText _speech;
  String? _listeningFieldKey;

  final List<Map<String, String>> _spots = [];
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _institutionalContacts = [];
  List<Map<String, dynamic>> _presenceCandidates = [];
  List<Map<String, String>> _personnelRows = [];
  Set<String> _selectedPresenceLabels = <String>{};
  Map<String, dynamic>? _presenceEntry;
  bool _presenceFromPlanning = false;
  bool _presenceSaving = false;
  bool _presenceAutoSaveAttempted = false;

  String? _selectedSpotId;
  String _selectedType = 'Observation';
  final Set<String> _selectedInterventionZones = <String>{};
  String? _victimSex;
  String _victimQualification = 'Idem';
  late DateTime _selectedDay;
  bool _restricted = false;
  bool _loading = true;
  bool _saving = false;
  bool _entryMutationInProgress = false;
  bool _sharingMainCourante = false;
  String? _statusMessage;

  // Référence visuelle : le label flottant du menu "Type de fait".
  // Les InputDecorator/TextField partent de 16 px puis Flutter les réduit
  // visuellement en label flottant. Les titres déjà posés dans le contenu
  // utilisent directement la taille visible finale de 12 px.
  static const TextStyle _fieldLabelStyle = TextStyle(
    color: SauveteurStyledDropdown.borderColor,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _visibleTitleStyle = TextStyle(
    color: SauveteurStyledDropdown.borderColor,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static const _victimSexOptions = <String>[
    'Féminin',
    'Masculin',
  ];

  static const _victimQualificationOptions = <String>[
    'Idem',
    'Urgence Relative',
    'Urgence Absolue',
    'Décédée',
  ];

  static const _types = <String>[
    'Observation',
    'Incident',
    'Intervention',
    'Personne recherchée',
    'Danger',
    'Météo exceptionnelle',
    'Matériel',
    'Information administrative',
    'Autre',
  ];

  static const _interventionZoneOptions = <String>[
    'Zone de bain surveillée',
    'Hors zone de bain surveillée',
    'Zone réglementée',
    'Hors zone réglementée',
  ];

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

  bool get _isSphotOn => widget.sphotMode.toUpperCase() == 'ON';

  bool get _isSupervisor => widget.canManageRestrictedOperationalData;

  bool get _canWrite => _isSphotOn && _isSupervisor;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _selectedDayIsToday {
    final today = _today;
    return _selectedDay.year == today.year &&
        _selectedDay.month == today.month &&
        _selectedDay.day == today.day;
  }

  String _formatSelectedDay(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
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
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _selectDay(DateTime day) async {
    if (day.isAfter(_today)) return;

    setState(() {
      _selectedDay = DateTime(day.year, day.month, day.day);
      _statusMessage = null;
      _presenceAutoSaveAttempted = false;
    });

    _scrollSelectedDayIntoView();
    await _loadEntries();
  }

  bool get _selectedMonthIsCurrentMonth {
    final today = _today;
    return _selectedDay.year == today.year &&
        _selectedDay.month == today.month;
  }

  Future<void> _changeMonth(int delta) async {
    final today = _today;
    final currentMonth = DateTime(today.year, today.month);
    final targetMonth = DateTime(
      _selectedDay.year,
      _selectedDay.month + delta,
    );

    if (targetMonth.isAfter(currentMonth)) return;

    final daysInTargetMonth = DateTime(
      targetMonth.year,
      targetMonth.month + 1,
      0,
    ).day;

    var targetDay = _selectedDay.day;
    if (targetDay > daysInTargetMonth) {
      targetDay = daysInTargetMonth;
    }

    if (targetMonth.year == today.year &&
        targetMonth.month == today.month &&
        targetDay > today.day) {
      targetDay = today.day;
    }

    setState(() {
      _selectedDay = DateTime(
        targetMonth.year,
        targetMonth.month,
        targetDay,
      );
      _statusMessage = null;
      _presenceAutoSaveAttempted = false;
    });

    _scrollSelectedDayIntoView();
    await _loadEntries();
  }

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _selectedDay = _today;
    _loadSpots();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollSelectedDayIntoView();
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _victimNameController.dispose();
    _victimFirstNameController.dispose();
    _victimAgeController.dispose();
    _victimBirthDateController.dispose();
    _victimResidenceController.dispose();
    _victimPhoneController.dispose();
    _dayScrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _loadSpots() async {
    final assigned = widget.postesAffectes.toSet();

    final territoryReference = FirebaseFirestore.instance
        .collection('territoires')
        .doc(widget.territoireId);

    final territorySnapshot = await territoryReference.get();
    final territoryData = territorySnapshot.data() ?? <String, dynamic>{};
    final rawInstitutionalContacts = territoryData['institutionnels'];
    final institutionalContacts = rawInstitutionalContacts is List
        ? rawInstitutionalContacts
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .where((contact) {
              return (contact['nom'] ?? '').toString().trim().isNotEmpty ||
                  (contact['prenom'] ?? '').toString().trim().isNotEmpty ||
                  (contact['fonction'] ?? '').toString().trim().isNotEmpty;
            })
            .toList()
        : <Map<String, dynamic>>[];

    final snapshot = await territoryReference
        .collection('spots')
        .where('typeSphot', isEqualTo: '🚨 POSTE DE SECOURS 🚨')
        .get();

    final spots = snapshot.docs
        .where((doc) => assigned.contains(doc.id))
        .map((doc) {
          final data = doc.data();
          final label = [
            (data['nomSecours'] ?? '').toString(),
            (data['nomSphot'] ?? '').toString(),
          ].where((value) => value.trim().isNotEmpty).join(' - ');

          return <String, String>{
            'id': doc.id,
            'label': label.isEmpty ? doc.id : label,
          };
        })
        .toList()
      ..sort((a, b) => a['label']!.compareTo(b['label']!));

    if (!mounted) return;

    setState(() {
      _spots
        ..clear()
        ..addAll(spots);
      final preferredId = widget.initialSpotId?.trim();
      final initialSpot = _spots.isEmpty
          ? null
          : _spots.firstWhere(
              (spot) => spot['id'] == preferredId,
              orElse: () => _spots.first,
            );
      _selectedSpotId = initialSpot?['id'];
      _institutionalContacts = institutionalContacts;
      _loading = false;
    });

    if (_selectedSpotId != null) {
      await _loadEntries();
    }
  }

  String _normalizePresenceName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-zà-öø-ÿ0-9]+"), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _planningCellMeansPresent(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty || value == '-') return false;

    final normalized = value.toLowerCase();
    return normalized != 'repos' &&
        normalized != 'repose' &&
        normalized != 'absent' &&
        !normalized.contains('congé') &&
        !normalized.contains('conge');
  }

  String _planningPersonnelStatus(String rawValue) {
    final value = rawValue.trim();
    final normalized = value.toLowerCase();

    if (_planningCellMeansPresent(value)) {
      return 'PRÉSENT';
    }

    if (normalized.contains('congé') || normalized.contains('conge')) {
      return 'ABSENT — CONGÉ';
    }

    if (normalized.contains('repos') || normalized.contains('repose')) {
      return 'ABSENT — REPOS';
    }

    if (normalized.contains('absent')) {
      return 'ABSENT';
    }

    return 'ABSENT — NON PLANIFIÉ';
  }

  String get _selectedPlanningMonthId {
    return '${_selectedDay.year}-'
        '${_selectedDay.month.toString().padLeft(2, '0')}';
  }

  bool _isPresenceEntry(Map<String, dynamic> entry) {
    final type = (entry['type'] ?? '').toString().trim().toLowerCase();
    return type == 'présence' || type == 'presence';
  }

  bool _isMaterialVerificationEntry(Map<String, dynamic> entry) {
    final type = (entry['type'] ?? '').toString().trim().toLowerCase();
    return type == 'vérification matériel' ||
        type == 'verification materiel' ||
        type == 'vérifications' ||
        type == 'verifications';
  }

  int _entryOccurredAtMillis(Map<String, dynamic> entry) {
    final raw = entry['occurredAt'];
    if (raw is num) return raw.toInt();
    return int.tryParse((raw ?? '').toString()) ?? 0;
  }

  int _compareFactEntries(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aIsMaterialVerification = _isMaterialVerificationEntry(a);
    final bIsMaterialVerification = _isMaterialVerificationEntry(b);

    if (aIsMaterialVerification != bIsMaterialVerification) {
      return aIsMaterialVerification ? -1 : 1;
    }

    return _entryOccurredAtMillis(a).compareTo(
      _entryOccurredAtMillis(b),
    );
  }

  List<String> _presenceDescriptionLines(Map<String, dynamic> entry) {
    final description = (entry['description'] ?? '').toString();
    return description
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where(
          (value) =>
              value.isNotEmpty &&
              value.toLowerCase() != 'aucun sauveteur présent.',
        )
        .toList();
  }

  Future<void> _loadPresenceContext(
    List<Map<String, dynamic>> entriesForSelectedDay,
  ) async {
    final spotId = _selectedSpotId;
    if (spotId == null || spotId.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _presenceCandidates = [];
          _personnelRows = [];
          _selectedPresenceLabels = <String>{};
          _presenceEntry = null;
          _presenceFromPlanning = false;
        });
      }
      return;
    }

    Map<String, dynamic>? existingPresence;
    for (final entry in entriesForSelectedDay) {
      if (_isPresenceEntry(entry)) {
        existingPresence = entry;
        break;
      }
    }

    final sauveteursSnapshot = await FirebaseFirestore.instance
        .collection('territoires')
        .doc(widget.territoireId)
        .collection('sauveteurs')
        .get();

    final candidates = <Map<String, dynamic>>[];
    for (final document in sauveteursSnapshot.docs) {
      final data = document.data();
      final assigned = data['postesAffectes'] is List
          ? (data['postesAffectes'] as List)
              .map((value) => value.toString())
              .toSet()
          : <String>{};

      if (!assigned.contains(spotId)) continue;

      final nom = (data['nom'] ?? '').toString().trim();
      final prenom = (data['prenom'] ?? '').toString().trim();
      final rawFunctions = data['fonctions'];
      final functions = rawFunctions is Iterable
          ? rawFunctions
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList()
          : <String>[];
      final label = [prenom, nom]
          .where((value) => value.isNotEmpty)
          .join(' ')
          .trim();

      if (label.isEmpty) continue;

      final login = (data['login'] ?? '').toString().trim().toLowerCase();
      final connected =
          login.isNotEmpty && login == widget.login.trim().toLowerCase();

      candidates.add({
        'id': document.id,
        'label': label,
        'login': login,
        'quality': functions.isEmpty ? 'Sauveteur' : functions.join(' / '),
        'planned': false,
        'connected': connected,
        'aliases': <String>[
          _normalizePresenceName(label),
          _normalizePresenceName([nom, prenom].join(' ')),
        ],
      });
    }

    final planningReference = FirebaseFirestore.instance
        .collection('territoires')
        .doc(widget.territoireId)
        .collection('spots')
        .doc(spotId)
        .collection('planningSauveteurs')
        .doc(_selectedPlanningMonthId);

    final planningSnapshot = await planningReference.get();
    final plannedLabels = <String>{};
    final personnelRows = <Map<String, String>>[];

    if (planningSnapshot.exists) {
      final planning = planningSnapshot.data() ?? <String, dynamic>{};
      final names = planning['names'] is Map
          ? Map<String, dynamic>.from(planning['names'] as Map)
          : <String, dynamic>{};
      final cells = planning['cells'] is Map
          ? Map<String, dynamic>.from(planning['cells'] as Map)
          : <String, dynamic>{};

      for (final entry in names.entries) {
        final role = entry.key.toString();
        final name = entry.value.toString().trim();
        if (name.isEmpty) continue;

        final cellKey = '$role-day_${_selectedDay.day}';
        final cellValue = (cells[cellKey] ?? '').toString();
        final plannedPresent = _planningCellMeansPresent(cellValue);

        personnelRows.add({
          'name': name,
          'quality': role,
          'planningStatus': _planningPersonnelStatus(cellValue),
        });

        final normalizedName = _normalizePresenceName(name);
        Map<String, dynamic>? matchedCandidate;

        for (final candidate in candidates) {
          final aliases = (candidate['aliases'] as List)
              .map((value) => value.toString())
              .toList();
          if (aliases.contains(normalizedName)) {
            matchedCandidate = candidate;
            break;
          }
        }

        if (matchedCandidate != null) {
          matchedCandidate['planningRole'] = role;
          if (plannedPresent) {
            matchedCandidate['planned'] = true;
            plannedLabels.add(matchedCandidate['label'].toString());
          }
        } else {
          candidates.add({
            'id': 'planning:$role',
            'label': name,
            'quality': role,
            'planningRole': role,
            'planned': plannedPresent,
            'connected': false,
            'aliases': <String>[normalizedName],
          });
          if (plannedPresent) {
            plannedLabels.add(name);
          }
        }
      }
    }

    candidates.sort(
      (a, b) => (a['label'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['label'] ?? '').toString().toLowerCase()),
    );

    Set<String> selected;
    if (existingPresence != null) {
      selected = _presenceDescriptionLines(existingPresence).toSet();

      for (final savedLabel in selected.toList()) {
        final normalized = _normalizePresenceName(savedLabel);
        final found = candidates.any((candidate) {
          final aliases = (candidate['aliases'] as List)
              .map((value) => value.toString())
              .toList();
          return aliases.contains(normalized);
        });

        if (!found) {
          candidates.add({
            'id': 'saved:$normalized',
            'label': savedLabel,
            'quality': 'Sauveteur',
            'planned': false,
            'connected': false,
            'aliases': <String>[normalized],
          });
        }
      }
    } else {
      selected = plannedLabels.toSet();

      if (_selectedDayIsToday) {
        for (final candidate in candidates) {
          if (candidate['connected'] == true) {
            final connectedLabel =
                (candidate['label'] ?? '').toString().trim();
            if (connectedLabel.isNotEmpty) {
              selected.add(connectedLabel);
            }
          }
        }
      }
    }

    final normalizedSelected = selected
        .map(_normalizePresenceName)
        .toSet();

    for (final row in personnelRows) {
      final name = row['name'] ?? '';
      final isPresent = normalizedSelected.contains(
        _normalizePresenceName(name),
      );
      final planningStatus = row['planningStatus'] ?? 'ABSENT';

      row['status'] = isPresent
          ? 'PRÉSENT'
          : planningStatus == 'PRÉSENT'
              ? 'ABSENT'
              : planningStatus;
    }

    for (final selectedLabel in selected) {
      final normalized = _normalizePresenceName(selectedLabel);
      final alreadyListed = personnelRows.any(
        (row) => _normalizePresenceName(row['name'] ?? '') == normalized,
      );
      if (alreadyListed) continue;

      Map<String, dynamic>? candidate;
      for (final value in candidates) {
        final aliases = (value['aliases'] as List)
            .map((item) => item.toString())
            .toList();
        if (aliases.contains(normalized)) {
          candidate = value;
          break;
        }
      }

      personnelRows.add({
        'name': selectedLabel,
        'quality': (candidate?['planningRole'] ??
                candidate?['quality'] ??
                'Sauveteur')
            .toString(),
        'planningStatus': 'PRÉSENT',
        'status': 'PRÉSENT',
      });
    }

    personnelRows.sort((a, b) {
      final aPresent = a['status'] == 'PRÉSENT';
      final bPresent = b['status'] == 'PRÉSENT';
      if (aPresent != bPresent) return aPresent ? -1 : 1;

      final qualityCompare =
          (a['quality'] ?? '').compareTo(b['quality'] ?? '');
      if (qualityCompare != 0) return qualityCompare;
      return (a['name'] ?? '').compareTo(b['name'] ?? '');
    });

    if (!mounted) return;

    setState(() {
      _presenceCandidates = candidates;
      _personnelRows = personnelRows;
      _selectedPresenceLabels = selected;
      _presenceEntry = existingPresence;
      _presenceFromPlanning = plannedLabels.isNotEmpty;
    });

    if (_selectedDayIsToday &&
        existingPresence == null &&
        selected.isNotEmpty &&
        !_presenceAutoSaveAttempted &&
        _canWrite) {
      _presenceAutoSaveAttempted = true;
      await _savePresence(automatic: true);
    }
  }

  Future<void> _savePresence({bool automatic = false}) async {
    if (!_canWrite ||
        _selectedSpotId == null ||
        _presenceSaving ||
        _entryMutationInProgress) {
      return;
    }

    final labels = _selectedPresenceLabels.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final description = labels.isEmpty
        ? 'Aucun sauveteur présent.'
        : labels.join('\n');

    final actionTaken = automatic
        ? _presenceFromPlanning
            ? 'Présence préremplie automatiquement depuis le planning.'
            : 'Présence initialisée automatiquement depuis la session sauveteur active.'
        : _presenceFromPlanning
            ? 'Présence issue du planning, vérifiée ou ajustée manuellement.'
            : 'Présence renseignée manuellement.';

    setState(() {
      _presenceSaving = true;
      _statusMessage = null;
    });

    try {
      final existingId = (_presenceEntry?['id'] ?? '').toString().trim();
      final endpoint = existingId.isEmpty
          ? 'addSauveteurMainCouranteEntry'
          : 'updateSauveteurMainCouranteEntry';

      final body = <String, dynamic>{
        'sauveteurSessionToken': widget.sauveteurSessionToken,
        'spotId': _selectedSpotId,
        'type': 'Présence',
        'description': description,
        'actionTaken': actionTaken,
        'visibility': 'operational',
        if (existingId.isNotEmpty) 'entryId': existingId,
      };

      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/$endpoint',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _statusMessage =
              'La présence n’a pas pu être enregistrée actuellement.';
        });
        return;
      }

      if (!automatic) {
        setState(() {
          _statusMessage = 'Présence du jour enregistrée.';
        });
      }

      await _loadEntries();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Impossible d’enregistrer la présence pour le moment.';
      });
    } finally {
      if (mounted) {
        setState(() => _presenceSaving = false);
      }
    }
  }

  Future<void> _openPresenceSelector() async {
    if (!_canWrite || !_selectedDayIsToday || _presenceSaving) return;

    final workingSelection = _selectedPresenceLabels.toSet();

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'PRÉSENCE',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: _presenceCandidates.isEmpty
                    ? const Text(
                        'Aucun sauveteur affecté à ce poste. '
                        'La présence peut être renseignée lorsque les '
                        'affectations ou le planning sont disponibles.',
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 430),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _presenceCandidates.length,
                          itemBuilder: (context, index) {
                            final candidate = _presenceCandidates[index];
                            final label =
                                (candidate['label'] ?? '').toString();
                            final planned =
                                candidate['planned'] == true;
                            final connected =
                                candidate['connected'] == true;
                            final checked =
                                workingSelection.contains(label);

                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: checked,
                              activeColor: const Color(0xFF1E3A8A),
                              title: Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                planned
                                    ? 'Prévu présent au planning'
                                    : connected
                                        ? 'Sauveteur connecté à ce poste'
                                        : 'Non prévu au planning / ajout manuel',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: planned
                                      ? const Color(0xFF15803D)
                                      : Colors.black54,
                                ),
                              ),
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    workingSelection.add(label);
                                  } else {
                                    workingSelection.remove(label);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('ANNULER'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(workingSelection);
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('ENREGISTRER'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedPresenceLabels = result;
    });
    await _savePresence();
  }

  Widget _presenceSelector() {
    final count = _selectedPresenceLabels.length;
    final summary = count == 0
        ? 'Aucun sauveteur présent'
        : count == 1
            ? _selectedPresenceLabels.first
            : '$count sauveteurs présents';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _canWrite && _selectedDayIsToday
          ? _openPresenceSelector
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Présence',
          labelStyle: _fieldLabelStyle,
          floatingLabelStyle: _fieldLabelStyle,
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF1E3A8A),
              width: 1.5,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF1E3A8A),
              width: 1.5,
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.groups_2_outlined,
              color: Color(0xFFDC2626),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_presenceSaving)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFFDC2626),
              ),
          ],
        ),
      ),
    );
  }

  Widget _personnelCard() {
    final presents = _personnelRows
        .where((row) => row['status'] == 'PRÉSENT')
        .toList();
    final absents = _personnelRows
        .where((row) => row['status'] != 'PRÉSENT')
        .toList();

    Widget personnelLine(Map<String, String> row, {required bool present}) {
      final name = (row['name'] ?? '').trim();
      final quality = (row['quality'] ?? 'Sauveteur').trim();
      final status = (row['status'] ?? '').trim();

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              present
                  ? Icons.check_circle_rounded
                  : Icons.remove_circle_outline_rounded,
              color: present
                  ? const Color(0xFF15803D)
                  : const Color(0xFFDC2626),
              size: 17,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    quality,
                    style: const TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              status,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: present
                    ? const Color(0xFF15803D)
                    : const Color(0xFFDC2626),
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Personnels',
        labelStyle: _fieldLabelStyle,
        floatingLabelStyle: _fieldLabelStyle,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: SauveteurStyledDropdown.borderColor,
            width: 1.6,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: SauveteurStyledDropdown.borderColor,
            width: 1.6,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (presents.isNotEmpty) ...[
            const Text(
              'PRÉSENTS',
              style: TextStyle(
                color: Color(0xFF15803D),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            ...presents.map((row) => personnelLine(row, present: true)),
          ],
          if (presents.isNotEmpty && absents.isNotEmpty)
            const Divider(height: 14),
          if (absents.isNotEmpty) ...[
            const Text(
              'ABSENTS',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            ...absents.map((row) => personnelLine(row, present: false)),
          ],
        ],
      ),
    );
  }

  Widget _derivedPastPresenceCard() {
    final labels = _selectedPresenceLabels.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E3A8A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Présence',
            style: _visibleTitleStyle,
          ),
          const SizedBox(height: 6),
          Text(
            labels.isEmpty
                ? 'Aucune présence renseignée.'
                : labels.join('\n'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (_presenceFromPlanning) ...[
            const SizedBox(height: 6),
            const Text(
              'Présence issue du planning de cette journée.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadEntries() async {
    if (_selectedSpotId == null) {
      if (mounted) setState(() => _entries = []);
      return;
    }

    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'getSauveteurMainCourante',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sauveteurSessionToken': widget.sauveteurSessionToken,
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
          _entries = [];
          _statusMessage =
              'La main courante réelle n’est pas accessible actuellement.';
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      final raw = decoded is Map<String, dynamic> && decoded['entries'] is List
          ? decoded['entries'] as List
          : const [];

      final dayStart = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
      ).millisecondsSinceEpoch;
      final dayEnd = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day + 1,
      ).millisecondsSinceEpoch;

      final entriesForSelectedDay = raw
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .where((entry) {
            final rawOccurredAt = entry['occurredAt'];
            final occurredAt = rawOccurredAt is num
                ? rawOccurredAt.toInt()
                : int.tryParse((rawOccurredAt ?? '').toString());
            if (occurredAt == null) return false;
            return occurredAt >= dayStart && occurredAt < dayEnd;
          })
          .toList();

      setState(() {
        _entries = entriesForSelectedDay;
      });

      await _loadPresenceContext(entriesForSelectedDay);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _statusMessage =
            'Impossible de charger la main courante pour le moment.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addEntry() async {
    if (!_canWrite || _selectedSpotId == null || _saving) return;

    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() {
        _statusMessage = 'Renseignez le fait du jour avant de l’enregistrer.';
      });
      return;
    }

    if (_selectedType == 'Intervention' &&
        !_hasCompleteInterventionZones(_selectedInterventionZones)) {
      setState(() {
        _statusMessage =
            'Pour une intervention, indiquez la situation de baignade '
            'et la situation réglementaire.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _statusMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'addSauveteurMainCouranteEntry',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sauveteurSessionToken': widget.sauveteurSessionToken,
          'spotId': _selectedSpotId,
          'type': _selectedType,
          'description': description,
          'actionTaken': '',
          'visibility': _restricted ? 'restricted' : 'operational',
          if (_selectedType == 'Intervention')
            'interventionZones': _selectedInterventionZones.toList(),
          if (_selectedType == 'Intervention')
            'victim': {
              'sexe': _victimSex ?? '',
              'nom': _victimNameController.text.trim(),
              'prenom': _victimFirstNameController.text.trim(),
              'age': _victimAgeController.text.trim(),
              'dateNaissance': _victimBirthDateController.text.trim(),
              'lieuHabitation': _victimResidenceController.text.trim(),
              'telephone': _victimPhoneController.text.trim(),
              'qualification': _victimQualification,
            },
        }),
      );

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _statusMessage =
              'Enregistrement refusé. Vérifiez que SPHOT est ON et que '
              'votre affectation est toujours active.';
        });
        return;
      }

      _descriptionController.clear();
      _victimNameController.clear();
      _victimFirstNameController.clear();
      _victimAgeController.clear();
      _victimBirthDateController.clear();
      _victimResidenceController.clear();
      _victimPhoneController.clear();
      setState(() {
        _restricted = false;
        _selectedType = 'Observation';
        _selectedInterventionZones.clear();
        _victimSex = null;
        _victimQualification = 'Idem';
        _statusMessage = 'Fait du jour enregistré dans la main courante.';
      });
      await _loadEntries();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Enregistrement impossible pour le moment.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateEntry(
    Map<String, dynamic> entry, {
    required String type,
    required String description,
    required String actionTaken,
    required bool restricted,
    Map<String, dynamic>? victim,
    List<String>? interventionZones,
  }) async {
    if (!_canWrite ||
        _selectedSpotId == null ||
        _entryMutationInProgress) {
      return;
    }

    final entryId = (entry['id'] ?? '').toString().trim();
    if (entryId.isEmpty) return;

    setState(() {
      _entryMutationInProgress = true;
      _statusMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'updateSauveteurMainCouranteEntry',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sauveteurSessionToken': widget.sauveteurSessionToken,
          'spotId': _selectedSpotId,
          'entryId': entryId,
          'type': type,
          'description': description,
          'actionTaken': actionTaken,
          'visibility': restricted ? 'restricted' : 'operational',
          if (type == 'Intervention')
            'interventionZones': interventionZones ?? <String>[],
          if (type == 'Intervention' || type == 'Secours')
            'victim': victim ?? <String, dynamic>{},
        }),
      );

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _statusMessage =
              'La modification de cette saisie a été refusée.';
        });
        return;
      }

      setState(() {
        _statusMessage = 'Saisie modifiée.';
      });
      await _loadEntries();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Impossible de modifier cette saisie pour le moment.';
      });
    } finally {
      if (mounted) {
        setState(() => _entryMutationInProgress = false);
      }
    }
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    if (!_canWrite || _entryMutationInProgress) return;

    final currentType =
        (entry['type'] ?? 'Observation').toString().trim();
    final dialogTypes = <String>{
      ..._types,
      if (currentType.isNotEmpty) currentType,
    }.toList();

    String selectedType =
        currentType.isEmpty ? 'Observation' : currentType;
    final selectedInterventionZones = entry['interventionZones'] is List
        ? (entry['interventionZones'] as List)
            .map((value) => value.toString())
            .where(_interventionZoneOptions.contains)
            .toSet()
        : <String>{};
    bool restricted =
        (entry['visibility'] ?? 'operational').toString() == 'restricted';

    final descriptionController = TextEditingController(
      text: (entry['description'] ?? '').toString(),
    );
    final existingActionTaken =
        (entry['actionTaken'] ?? '').toString();
    final currentVictim = entry['victim'] is Map
        ? Map<String, dynamic>.from(entry['victim'] as Map)
        : <String, dynamic>{};
    String? victimSex = (currentVictim['sexe'] ?? '').toString().trim();
    if (!_victimSexOptions.contains(victimSex)) {
      victimSex = null;
    }
    String victimQualification =
        (currentVictim['qualification'] ?? 'Idem').toString();
    if (!_victimQualificationOptions.contains(victimQualification)) {
      victimQualification = 'Idem';
    }
    final victimNameController = TextEditingController(
      text: (currentVictim['nom'] ?? '').toString(),
    );
    final victimFirstNameController = TextEditingController(
      text: (currentVictim['prenom'] ?? '').toString(),
    );
    final victimAgeController = TextEditingController(
      text: (currentVictim['age'] ?? '').toString(),
    );
    final victimBirthDateController = TextEditingController(
      text: (currentVictim['dateNaissance'] ?? '').toString(),
    );
    final victimResidenceController = TextEditingController(
      text: (currentVictim['lieuHabitation'] ?? '').toString(),
    );
    final victimPhoneController = TextEditingController(
      text: _formatFrenchPhone((currentVictim['telephone'] ?? '').toString()),
    );
    _syncVictimAge(
      victimBirthDateController,
      victimAgeController,
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'MODIFIER LA SAISIE',
                style: TextStyle(
                  color: Color(0xFF8E24AA),
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SauveteurStyledDropdown(
                        labelText: 'Type de fait',
                        value: selectedType,
                        options: dialogTypes
                            .map(
                              (type) => SauveteurDropdownOption(
                                value: type,
                                label: type,
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() => selectedType = value);
                        },
                      ),
                      if (selectedType == 'Intervention') ...[
                        const SizedBox(height: 12),
                        _interventionZonesSelector(
                          selected: selectedInterventionZones,
                          onToggle: (option) {
                            setDialogState(() {
                              _toggleInterventionZone(
                                selectedInterventionZones,
                                option,
                              );
                            });
                          },
                        ),
                      ],
                      if (selectedType == 'Intervention' ||
                          selectedType == 'Secours') ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFDC2626),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'VICTIME',
                                style: TextStyle(
                                  color: _victimBlue,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SauveteurStyledDropdown(
                                labelText: 'Sexe',
                                value: victimSex,
                                valueColor: _victimBlue,
                                options: _victimSexOptions
                                    .map(
                                      (value) => SauveteurDropdownOption(
                                        value: value,
                                        label: value,
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setDialogState(() => victimSex = value);
                                },
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: victimNameController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: const [
                                  _UpperCaseTextFormatter(),
                                ],
                                style: const TextStyle(
                                  color: _victimBlue,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: _victimInputDecoration(
                                  'Nom',
                                  suffixIcon: _microphoneButton(
                                    'editVictimName',
                                    victimNameController,
                                    transform: (value) => value.toUpperCase(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: victimFirstNameController,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: const [
                                  _FirstLetterUpperCaseTextFormatter(),
                                ],
                                style: const TextStyle(
                                  color: _victimBlue,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: _victimInputDecoration(
                                  'Prénom',
                                  suffixIcon: _microphoneButton(
                                    'editVictimFirstName',
                                    victimFirstNameController,
                                    transform: _capitalizeVictimFirstName,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _victimBirthDateAgeRow(
                                birthDateController: victimBirthDateController,
                                ageController: victimAgeController,
                                onBirthDateTap: () async {
                                  final picked = await _pickVictimBirthDate(
                                    dialogContext,
                                    victimBirthDateController.text,
                                  );
                                  if (picked == null) return;

                                  setDialogState(() {
                                    victimBirthDateController.text =
                                        _formatVictimBirthDate(picked);
                                    _syncVictimAge(
                                      victimBirthDateController,
                                      victimAgeController,
                                    );
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: victimResidenceController,
                                style: const TextStyle(
                                  color: _victimBlue,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: _victimInputDecoration(
                                  'Lieu d’habitation',
                                  suffixIcon: _microphoneButton(
                                    'editVictimResidence',
                                    victimResidenceController,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: victimPhoneController,
                                keyboardType: TextInputType.phone,
                                inputFormatters: const [
                                  _FrenchPhoneInputFormatter(),
                                ],
                                style: const TextStyle(
                                  color: _victimBlue,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                                decoration: _victimInputDecoration(
                                  'Numéro de téléphone',
                                  hintText: '06 12 34 56 78',
                                  suffixIcon: _microphoneButton(
                                    'editVictimPhone',
                                    victimPhoneController,
                                    transform: _formatSpokenFrenchPhone,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SauveteurStyledDropdown(
                                labelText: 'Qualification',
                                value: victimQualification,
                                valueColor: _victimBlue,
                                options: _victimQualificationOptions
                                    .map(
                                      (value) => SauveteurDropdownOption(
                                        value: value,
                                        label: value,
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setDialogState(
                                    () => victimQualification = value,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        minLines: 3,
                        maxLines: 7,
                        decoration: InputDecoration(
                          labelText: 'Fait du jour',
                          suffixIcon: _microphoneButton(
                            'editFact',
                            descriptionController,
                          ),
                          labelStyle: _fieldLabelStyle,
                          floatingLabelStyle: _fieldLabelStyle,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: SauveteurStyledDropdown.borderColor,
                              width: 1.6,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: SauveteurStyledDropdown.borderColor,
                              width: 1.6,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: SauveteurStyledDropdown.borderColor,
                              width: 1.8,
                            ),
                          ),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Information restreinte',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        value: restricted,
                        onChanged: (value) {
                          setDialogState(() => restricted = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('ANNULER'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final description =
                        descriptionController.text.trim();
                    if (description.isEmpty) return;
                    if (selectedType == 'Intervention' &&
                        !_hasCompleteInterventionZones(
                          selectedInterventionZones,
                        )) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Indiquez la situation de baignade et la '
                            'situation réglementaire.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop({
                      'type': selectedType,
                      'description': description,
                      'actionTaken': existingActionTaken,
                      'restricted': restricted,
                      if (selectedType == 'Intervention')
                        'interventionZones':
                            selectedInterventionZones.toList(),
                      if (selectedType == 'Intervention' ||
                          selectedType == 'Secours')
                        'victim': {
                          'sexe': victimSex ?? '',
                          'nom': victimNameController.text.trim(),
                          'prenom': victimFirstNameController.text.trim(),
                          'age': victimAgeController.text.trim(),
                          'dateNaissance':
                              victimBirthDateController.text.trim(),
                          'lieuHabitation':
                              victimResidenceController.text.trim(),
                          'telephone': victimPhoneController.text.trim(),
                          'qualification': victimQualification,
                        },
                    });
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text(
                    'ENREGISTRER',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8E24AA),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    descriptionController.dispose();
    victimNameController.dispose();
    victimFirstNameController.dispose();
    victimAgeController.dispose();
    victimBirthDateController.dispose();
    victimResidenceController.dispose();
    victimPhoneController.dispose();

    if (result == null) return;

    await _updateEntry(
      entry,
      type: (result['type'] ?? 'Observation').toString(),
      description: (result['description'] ?? '').toString(),
      actionTaken: (result['actionTaken'] ?? '').toString(),
      restricted: result['restricted'] == true,
      victim: result['victim'] is Map
          ? Map<String, dynamic>.from(result['victim'] as Map)
          : null,
      interventionZones: result['interventionZones'] is List
          ? (result['interventionZones'] as List)
              .map((value) => value.toString())
              .toList()
          : null,
    );
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    if (!_canWrite || _entryMutationInProgress) return;

    final entryId = (entry['id'] ?? '').toString().trim();
    if (entryId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'SUPPRIMER LA SAISIE',
          style: TextStyle(
            color: Color(0xFFDC2626),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Cette saisie sera retirée de la main courante. '
          'L’opération sera conservée dans le journal technique d’audit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ANNULER'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text(
              'SUPPRIMER',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _entryMutationInProgress = true;
      _statusMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'deleteSauveteurMainCouranteEntry',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sauveteurSessionToken': widget.sauveteurSessionToken,
          'spotId': _selectedSpotId,
          'entryId': entryId,
        }),
      );

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _statusMessage =
              'La suppression de cette saisie a été refusée.';
        });
        return;
      }

      setState(() {
        _statusMessage = 'Saisie supprimée.';
      });
      await _loadEntries();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Impossible de supprimer cette saisie pour le moment.';
      });
    } finally {
      if (mounted) {
        setState(() => _entryMutationInProgress = false);
      }
    }
  }

  String get _selectedSpotLabel {
    final spotId = _selectedSpotId;
    if (spotId == null || spotId.isEmpty) return 'Poste non renseigné';

    for (final spot in _spots) {
      if (spot['id'] == spotId) {
        final label = (spot['label'] ?? '').trim();
        if (label.isNotEmpty) return label;
      }
    }

    return spotId;
  }

  String _mainCouranteExportFileName() {
    final rawSpot = _selectedSpotLabel
        .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    final day = _selectedDay.day.toString().padLeft(2, '0');
    final month = _selectedDay.month.toString().padLeft(2, '0');

    return 'SPHOT_Main_courante_${rawSpot.isEmpty ? 'poste' : rawSpot}_'
        '${_selectedDay.year}-$month-$day.pdf';
  }

  List<Map<String, dynamic>> _entriesForExport() {
    final visibleEntries = _entries
        .where(
          (entry) =>
              !_selectedDayIsToday || !_isPresenceEntry(entry),
        )
        .toList();

    final verificationEntries = visibleEntries
        .where(_isMaterialVerificationEntry)
        .toList();
    final chronologicalEntries = visibleEntries
        .where((entry) => !_isMaterialVerificationEntry(entry))
        .toList()
      ..sort(_compareFactEntries);

    final verificationGroups =
        _materialVerificationGroups(verificationEntries);

    return <Map<String, dynamic>>[
      ...verificationGroups.map(_verificationGroupForExport),
      ...chronologicalEntries,
    ];
  }

  Future<Uint8List> _buildMainCourantePdf() async {
    final document = pw.Document();
    final exportEntries = _entriesForExport();

    pw.Widget sectionTitle(String title) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey300,
          border: pw.Border.all(color: PdfColors.black, width: 0.7),
        ),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
    }

    pw.Widget personnelLine(Map<String, String> row) {
      final status = (row['status'] ?? '').trim();
      final present = status == 'PRÉSENT';

      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
              color: PdfColors.grey300,
              width: 0.4,
            ),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                (row['name'] ?? '').trim(),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                (row['quality'] ?? 'Sauveteur').trim(),
                style: const pw.TextStyle(fontSize: 8.5),
              ),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                status,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: present ? PdfColors.green : PdfColors.red,
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget factCard(Map<String, dynamic> entry) {
      final createdBy = entry['createdBy'] is Map
          ? Map<String, dynamic>.from(entry['createdBy'] as Map)
          : <String, dynamic>{};
      final role = (createdBy['role'] ?? '').toString().trim();
      final action = (entry['actionTaken'] ?? '').toString().trim();
      final visibility = (entry['visibility'] ?? 'operational').toString();
      final restricted = visibility == 'restricted';
      final victim = entry['victim'] is Map
          ? Map<String, dynamic>.from(entry['victim'] as Map)
          : <String, dynamic>{};

      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(
            color: restricted ? PdfColors.purple : PdfColors.grey600,
            width: restricted ? 1 : 0.6,
          ),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    (entry['type'] ?? 'Observation').toString(),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                if (restricted)
                  pw.Text(
                    'RESTREINT',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.purple,
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              _formatDate(entry['occurredAt']),
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              _entryDescriptionForDisplay(entry),
              style: const pw.TextStyle(fontSize: 9),
            ),
            if (entry['interventionZones'] is List &&
                (entry['interventionZones'] as List).isNotEmpty) ...[
              pw.SizedBox(height: 5),
              pw.Text(
                'Zone : ' +
                    (entry['interventionZones'] as List)
                        .map((value) => value.toString())
                        .join(' • '),
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
            if (<String>{'intervention', 'secours'}.contains(
                  (entry['type'] ?? '').toString().toLowerCase(),
                ) &&
                victim.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                color: PdfColors.red50,
                child: pw.Text(
                  [
                    if ((victim['sexe'] ?? '').toString().trim().isNotEmpty)
                      'Sexe : ${victim['sexe']}',
                    if ((victim['nom'] ?? '').toString().trim().isNotEmpty)
                      'Nom : ${victim['nom']}',
                    if ((victim['prenom'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      'Prénom : ${victim['prenom']}',
                    if ((victim['age'] ?? '').toString().trim().isNotEmpty)
                      'Age : ${victim['age']}',
                    if ((victim['dateNaissance'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      'Date de naissance : ${victim['dateNaissance']}',
                    if ((victim['lieuHabitation'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      'Lieu d’habitation : ${victim['lieuHabitation']}',
                    if ((victim['telephone'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      'Téléphone : ${victim['telephone']}',
                    if ((victim['qualification'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      'Qualification : ${victim['qualification']}',
                  ].join('\n'),
                  style: const pw.TextStyle(fontSize: 8.2),
                ),
              ),
            ],
            if (action.isNotEmpty) ...[
              pw.SizedBox(height: 5),
              pw.Text(
                'Suite donnée : $action',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
            if (role.isNotEmpty) ...[
              pw.SizedBox(height: 5),
              pw.Text(
                'Saisi par : $role',
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ],
        ),
      );
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 28),
        build: (context) => [
          pw.Text(
            'SPHOT - MAIN COURANTE',
            style: pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Poste : $_selectedSpotLabel',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
          pw.Text(
            'Journée du ${_formatSelectedDay(_selectedDay)}',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
          pw.SizedBox(height: 12),

          if (_institutionalContacts.isNotEmpty) ...[
            sectionTitle('CONTACTS INSTITUTIONNELS'),
            pw.SizedBox(height: 5),
            ..._institutionalContacts.map((contact) {
              final identity = [
                (contact['civilite'] ?? '').toString().trim(),
                (contact['prenom'] ?? '').toString().trim(),
                (contact['nom'] ?? '').toString().trim(),
              ].where((value) => value.isNotEmpty).join(' ');
              final fonction =
                  (contact['fonction'] ?? '').toString().trim();
              final telephone =
                  (contact['telephone'] ?? '').toString().trim();
              final email = (contact['email'] ?? '').toString().trim();

              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(
                  [
                    identity,
                    fonction,
                    telephone,
                    email,
                  ].where((value) => value.isNotEmpty).join(' - '),
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
              );
            }),
            pw.SizedBox(height: 10),
          ],

          if (_personnelRows.isNotEmpty) ...[
            sectionTitle('PERSONNELS'),
            pw.SizedBox(height: 5),
            pw.Row(
              children: [
                pw.Expanded(
                  flex: 4,
                  child: pw.Text(
                    'Nom',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 4,
                  child: pw.Text(
                    'Qualité',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    'Situation',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            ..._personnelRows.map(personnelLine),
            pw.SizedBox(height: 12),
          ],

          sectionTitle('FAITS'),
          pw.SizedBox(height: 7),

          if (exportEntries.isEmpty)
            pw.Text(
              'Aucun fait enregistré pour cette journée.',
              style: const pw.TextStyle(fontSize: 9),
            )
          else
            ...exportEntries.map(factCard),

          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColors.grey500),
          pw.Text(
            'Document généré depuis SPHOT.',
            style: const pw.TextStyle(
              fontSize: 7.5,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  Future<void> _shareMainCourante() async {
    if (_sharingMainCourante || _selectedSpotId == null) return;

    setState(() => _sharingMainCourante = true);

    try {
      final bytes = await _buildMainCourantePdf();
      final fileName = _mainCouranteExportFileName();

      Rect? shareOrigin;
      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        shareOrigin =
            renderObject.localToGlobal(Offset.zero) & renderObject.size;
      }

      await SharePlus.instance.share(
        ShareParams(
          subject:
              'Main courante SPHOT - ${_formatSelectedDay(_selectedDay)}',
          text: 'Main courante SPHOT du poste $_selectedSpotLabel - '
              '${_formatSelectedDay(_selectedDay)}.',
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'application/pdf',
              name: fileName,
            ),
          ],
          sharePositionOrigin: shareOrigin,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sharingMainCourante = false);
      }
    }
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
    final selectedMonth = DateTime(
      _selectedDay.year,
      _selectedDay.month,
    );
    final daysInMonth = DateTime(
      selectedMonth.year,
      selectedMonth.month + 1,
      0,
    ).day;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1E3A8A),
          width: 1.3,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 30,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Mois précédent',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 30,
                  ),
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: Color(0xFF1E3A8A),
                    size: 24,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${_months[selectedMonth.month - 1]} '
                    '${selectedMonth.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Mois suivant',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 30,
                  ),
                  onPressed: _selectedMonthIsCurrentMonth
                      ? null
                      : () => _changeMonth(1),
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: _selectedMonthIsCurrentMonth
                        ? Colors.black26
                        : const Color(0xFF1E3A8A),
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 34,
            child: ListView.builder(
              controller: _dayScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: daysInMonth,
              itemBuilder: (context, index) {
                final day = index + 1;
                final date = DateTime(
                  selectedMonth.year,
                  selectedMonth.month,
                  day,
                );
                final selected = _selectedDay.year == date.year &&
                    _selectedDay.month == date.month &&
                    _selectedDay.day == date.day;
                final future = date.isAfter(today);

                return Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: future ? null : () => _selectDay(date),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF8E24AA)
                            : future
                                ? Colors.black.withOpacity(0.04)
                                : Colors.white.withOpacity(0.82),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF8E24AA)
                              : const Color(0xFF1E3A8A).withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : future
                                  ? Colors.black26
                                  : const Color(0xFF1E3A8A),
                          fontSize: 11,
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

  Widget _selectedDayHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'JOURNÉE DU ${_formatSelectedDay(_selectedDay)}',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _institutionalContactsCard() {
    if (_institutionalContacts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1E3A8A),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_outlined,
                color: Color(0xFF1E3A8A),
                size: 20,
              ),
              SizedBox(width: 7),
              Text(
                'CONTACTS INSTITUTIONNELS',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Spacer(),
              Text(
                'LECTURE SEULE',
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._institutionalContacts.asMap().entries.map((entry) {
            final contact = entry.value;
            final identity = [
              (contact['civilite'] ?? '').toString().trim(),
              (contact['prenom'] ?? '').toString().trim(),
              (contact['nom'] ?? '').toString().trim(),
            ].where((value) => value.isNotEmpty).join(' ');
            final fonction = (contact['fonction'] ?? '').toString().trim();
            final telephone = (contact['telephone'] ?? '').toString().trim();
            final email = (contact['email'] ?? '').toString().trim();

            return Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == _institutionalContacts.length - 1 ? 0 : 9,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC).withOpacity(0.88),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identity.isEmpty ? 'Contact institutionnel' : identity,
                      style: const TextStyle(
                        color: Color(0xFF1E3A8A),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (fonction.isNotEmpty)
                      Text(
                        fonction,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (telephone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone_outlined,
                            size: 15,
                            color: Color(0xFF1E3A8A),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              telephone,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.email_outlined,
                            size: 15,
                            color: Color(0xFF1E3A8A),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              email,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _materialVerificationCategory(
    Map<String, dynamic> entry,
  ) {
    final description =
        (entry['description'] ?? '').toString().toLowerCase();

    if (description.contains('catégorie : secours') ||
        description.contains('categorie : secours') ||
        description.contains('catégorie : oxy') ||
        description.contains('categorie : oxy') ||
        description.contains('dsa') ||
        description.contains('bouteille principale')) {
      return 'SECOURS';
    }

    if (description.contains('catégorie : phonie') ||
        description.contains('categorie : phonie') ||
        description.contains('communication') ||
        description.contains('vhf')) {
      return 'PHONIE';
    }

    if (description.contains('catégorie : matériel roulant') ||
        description.contains('categorie : materiel roulant') ||
        description.contains('véhicules / quads') ||
        description.contains('vehicules / quads')) {
      return 'MATÉRIEL ROULANT';
    }

    if (description.contains('catégorie : matériel flottant') ||
        description.contains('categorie : materiel flottant') ||
        description.contains('embarcations / jets') ||
        description.contains('rescue tubes')) {
      return 'MATÉRIEL FLOTTANT';
    }

    return 'VÉRIFICATION';
  }

  String _materialVerificationBody(
    Map<String, dynamic> entry,
  ) {
    final description = (entry['description'] ?? '').toString();
    final lines = description.split(RegExp(r'\r?\n')).toList();

    if (lines.isNotEmpty) {
      final first = lines.first.trim().toLowerCase();
      if (first.startsWith('catégorie :') ||
          first.startsWith('categorie :')) {
        lines.removeAt(0);
      }
    }

    return lines.join('\n').replaceAll(' • ', '\n').trim();
  }

  String _verificationTime(Map<String, dynamic> entry) {
    final millis = _entryOccurredAtMillis(entry);
    if (millis <= 0) return '--h--';

    final date = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  List<List<Map<String, dynamic>>> _materialVerificationGroups(
    List<Map<String, dynamic>> entries,
  ) {
    final ordered = entries.toList()
      ..sort(
        (a, b) => _entryOccurredAtMillis(a).compareTo(
          _entryOccurredAtMillis(b),
        ),
      );

    final categoryOccurrences = <String, int>{};
    final groups = <List<Map<String, dynamic>>>[];

    for (final entry in ordered) {
      final category = _materialVerificationCategory(entry);
      final occurrence = categoryOccurrences[category] ?? 0;
      categoryOccurrences[category] = occurrence + 1;

      while (groups.length <= occurrence) {
        groups.add(<Map<String, dynamic>>[]);
      }

      groups[occurrence].add(entry);
    }

    for (final group in groups) {
      group.sort(
        (a, b) => _entryOccurredAtMillis(a).compareTo(
          _entryOccurredAtMillis(b),
        ),
      );
    }

    return groups;
  }

  Map<String, dynamic> _verificationGroupForExport(
    List<Map<String, dynamic>> group,
  ) {
    final firstMillis = group.isEmpty
        ? 0
        : group
            .map(_entryOccurredAtMillis)
            .reduce((a, b) => a < b ? a : b);

    final description = group.map((entry) {
      final category = _materialVerificationCategory(entry);
      final time = _verificationTime(entry).replaceAll(':', 'h');
      final body = _materialVerificationBody(entry);
      return '$category — $time\n$body';
    }).join('\n\n');

    return <String, dynamic>{
      'id': 'verification-group-$firstMillis',
      'type': 'VÉRIFICATIONS',
      'description': description,
      'actionTaken': '',
      'visibility': 'operational',
      'occurredAt': firstMillis,
      'createdBy': <String, dynamic>{},
      'source': 'verification_group',
    };
  }

  Widget _verificationGroupCard(
    List<Map<String, dynamic>> group,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF8E24AA).withOpacity(0.55),
          width: 1.4,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Transform.rotate(
                angle: -0.20,
                child: Text(
                  'SPHOT • ${widget.login.toUpperCase()} • CONSULTATION RÉSERVÉE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.055),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VÉRIFICATIONS',
                  style: TextStyle(
                    color: Color(0xFF8E24AA),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 9),
                ...group.map((entry) {
                  final category =
                      _materialVerificationCategory(entry);
                  final body = _materialVerificationBody(entry);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.68),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF1E3A8A)
                              .withOpacity(0.28),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                    color: Color(0xFF1E3A8A),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                _verificationTime(entry),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          if (body.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              body,
                              style: const TextStyle(
                                fontSize: 11.2,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ],
                          if (_canWrite) ...[
                            const SizedBox(height: 3),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Modifier',
                                    visualDensity:
                                        VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    onPressed:
                                        _entryMutationInProgress
                                            ? null
                                            : () => _editEntry(entry),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: Color(0xFF1E3A8A),
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Supprimer',
                                    visualDensity:
                                        VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    onPressed:
                                        _entryMutationInProgress
                                            ? null
                                            : () => _deleteEntry(entry),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFDC2626),
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _entryDescriptionForDisplay(Map<String, dynamic> entry) {
    final type = (entry['type'] ?? '').toString().trim().toLowerCase();
    final description = (entry['description'] ?? '').toString();

    if (type == 'vérification matériel' ||
        type == 'verification materiel') {
      return description.replaceAll(' • ', '\n');
    }

    return description;
  }

  Widget _entryCard(Map<String, dynamic> entry) {
    final createdBy = entry['createdBy'] is Map
        ? Map<String, dynamic>.from(entry['createdBy'] as Map)
        : <String, dynamic>{};
    final role = (createdBy['role'] ?? '').toString();
    final visibility = (entry['visibility'] ?? 'operational').toString();
    final source = (entry['source'] ?? '').toString().trim();
    final automatic = source.startsWith('automatic_');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: visibility == 'restricted'
              ? const Color(0xFF8E24AA)
              : Colors.black26,
          width: 1.4,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Transform.rotate(
                angle: -0.20,
                child: Text(
                  'SPHOT • ${widget.login.toUpperCase()} • CONSULTATION RÉSERVÉE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.055),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (entry['type'] ?? 'Observation').toString(),
                        style: _visibleTitleStyle,
                      ),
                    ),
                    if (automatic)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFFF59E0B),
                          ),
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
                    if (visibility == 'restricted')
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Text(
                          'RESTREINT',
                          style: TextStyle(
                            color: Color(0xFF7E22CE),
                            fontSize: 9,
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
                  _entryDescriptionForDisplay(entry),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (entry['interventionZones'] is List &&
                    (entry['interventionZones'] as List).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: (entry['interventionZones'] as List)
                        .map(
                          (value) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFF1E3A8A)
                                    .withOpacity(0.35),
                              ),
                            ),
                            child: Text(
                              value.toString(),
                              style: const TextStyle(
                                color: Color(0xFF1E3A8A),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (<String>{'intervention', 'secours'}.contains(
                      (entry['type'] ?? '').toString().toLowerCase(),
                    ) &&
                    entry['victim'] is Map) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final victim =
                          Map<String, dynamic>.from(entry['victim'] as Map);
                      final lines = <String>[
                        if ((victim['sexe'] ?? '').toString().trim().isNotEmpty)
                          'Sexe : ${victim['sexe']}',
                        if ((victim['nom'] ?? '').toString().trim().isNotEmpty)
                          'Nom : ${victim['nom']}',
                        if ((victim['prenom'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          'Prénom : ${victim['prenom']}',
                        if ((victim['age'] ?? '').toString().trim().isNotEmpty)
                          'Age : ${victim['age']}',
                        if ((victim['dateNaissance'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          'Date de naissance : ${victim['dateNaissance']}',
                        if ((victim['lieuHabitation'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          'Lieu d’habitation : ${victim['lieuHabitation']}',
                        if ((victim['telephone'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          'Téléphone : ${victim['telephone']}',
                        if ((victim['qualification'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          'Qualification : ${victim['qualification']}',
                      ];

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2).withOpacity(0.88),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFDC2626).withOpacity(0.45),
                          ),
                        ),
                        child: Text(
                          lines.join('\n'),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      );
                    },
                  ),
                ],
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
                if (role.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Saisi par : $role',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_canWrite) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Modifier',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          onPressed: _entryMutationInProgress
                              ? null
                              : () => _editEntry(entry),
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Color(0xFF1E3A8A),
                            size: 20,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          onPressed: _entryMutationInProgress
                              ? null
                              : () => _deleteEntry(entry),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFDC2626),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _factsSection() {
    final visibleEntries = _entries
        .where(
          (entry) =>
              !_selectedDayIsToday || !_isPresenceEntry(entry),
        )
        .toList()
      ..sort(_compareFactEntries);

    final materialVerificationEntries = visibleEntries
        .where(_isMaterialVerificationEntry)
        .toList();
    final materialVerificationGroups =
        _materialVerificationGroups(materialVerificationEntries);
    final chronologicalEntries = visibleEntries
        .where((entry) => !_isMaterialVerificationEntry(entry))
        .toList();

    final showDerivedPresence = !_selectedDayIsToday &&
        _presenceEntry == null &&
        (_presenceFromPlanning || _selectedPresenceLabels.isNotEmpty);

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Faits',
        labelStyle: _fieldLabelStyle,
        floatingLabelStyle: _fieldLabelStyle,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: SauveteurStyledDropdown.borderColor,
            width: 1.6,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: SauveteurStyledDropdown.borderColor,
            width: 1.6,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...materialVerificationGroups.map(_verificationGroupCard),
          if (showDerivedPresence)
            _derivedPastPresenceCard(),
          if (materialVerificationEntries.isEmpty &&
              chronologicalEntries.isEmpty &&
              !showDerivedPresence)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 16,
              ),
              child: Text(
                'Aucun fait enregistré pour cette journée.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            ...chronologicalEntries.map(_entryCard),
        ],
      ),
    );
  }

  static const Color _victimBlue = Color(0xFF1E3A8A);

  String _capitalizeVictimFirstName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  String _formatSpokenFrenchPhone(String value) {
    final directDigits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (directDigits.isNotEmpty) {
      return _formatFrenchPhone(directDigits);
    }

    const digitWords = <String, String>{
      'zero': '0',
      'zéro': '0',
      'un': '1',
      'une': '1',
      'deux': '2',
      'trois': '3',
      'quatre': '4',
      'cinq': '5',
      'six': '6',
      'sept': '7',
      'huit': '8',
      'neuf': '9',
    };

    final tokens = value
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-zà-öø-ÿ0-9]+"), ' ')
        .trim()
        .split(RegExp(r'\s+'));

    final digits = tokens
        .map((token) => digitWords[token] ?? '')
        .join();

    return _formatFrenchPhone(digits);
  }

  Future<void> _listenToTextField(
    String fieldKey,
    TextEditingController controller, {
    String Function(String value)? transform,
  }) async {
    if (_speech.isListening && _listeningFieldKey == fieldKey) {
      await _speech.stop();
      if (mounted) {
        setState(() => _listeningFieldKey = null);
      }
      return;
    }

    if (_speech.isListening) {
      await _speech.stop();
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listeningFieldKey = null);
        }
      },
    );

    if (!available || !mounted) return;

    setState(() => _listeningFieldKey = fieldKey);

    await _speech.listen(
      localeId: 'fr_FR',
      onResult: (result) {
        if (!mounted) return;

        var text = result.recognizedWords;
        if (transform != null) {
          text = transform(text);
        }

        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );

        if (result.finalResult) {
          setState(() => _listeningFieldKey = null);
        }
      },
    );
  }

  Widget _microphoneButton(
    String fieldKey,
    TextEditingController controller, {
    String Function(String value)? transform,
  }) {
    final listening =
        _speech.isListening && _listeningFieldKey == fieldKey;

    return IconButton(
      tooltip: 'Dicter',
      onPressed: () => _listenToTextField(
        fieldKey,
        controller,
        transform: transform,
      ),
      icon: Icon(
        listening ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: listening ? Colors.red : _victimBlue,
        size: 21,
      ),
    );
  }

  String _formatFrenchPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digits.length > 10 ? digits.substring(0, 10) : digits;
    final groups = <String>[];
    for (var i = 0; i < limited.length; i += 2) {
      final end = (i + 2 < limited.length) ? i + 2 : limited.length;
      groups.add(limited.substring(i, end));
    }
    return groups.join(' ');
  }

  InputDecoration _victimInputDecoration(
    String label, {
    String? hintText,
    double labelFontSize = 16,
    FloatingLabelBehavior? floatingLabelBehavior,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      suffixIcon: suffixIcon,
      floatingLabelBehavior: floatingLabelBehavior,
      labelStyle: TextStyle(
        color: _victimBlue,
        fontSize: labelFontSize,
        fontWeight: FontWeight.w700,
      ),
      floatingLabelStyle: TextStyle(
        color: _victimBlue,
        fontSize: labelFontSize,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: TextStyle(
        color: _victimBlue.withOpacity(0.55),
        fontWeight: FontWeight.w600,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _victimBlue, width: 1.4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _victimBlue, width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _victimBlue, width: 1.8),
      ),
    );
  }

  DateTime? _parseVictimBirthDate(String value) {
    final match = RegExp(
      r'^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})$',
    ).firstMatch(value.trim());

    if (match == null) return null;

    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;

    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }

    return date;
  }

  String _formatVictimBirthDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return day + '/' + month + '/' + date.year.toString();
  }

  int _victimAgeAt(DateTime birthDate, DateTime referenceDate) {
    var age = referenceDate.year - birthDate.year;
    final birthdayPassed = referenceDate.month > birthDate.month ||
        (referenceDate.month == birthDate.month &&
            referenceDate.day >= birthDate.day);

    if (!birthdayPassed) age -= 1;
    return age < 0 ? 0 : age;
  }

  void _syncVictimAge(
    TextEditingController birthDateController,
    TextEditingController ageController,
  ) {
    final birthDate = _parseVictimBirthDate(birthDateController.text);
    if (birthDate == null) {
      ageController.clear();
      return;
    }

    ageController.text = _victimAgeAt(birthDate, _selectedDay).toString();
  }

  Future<DateTime?> _pickVictimBirthDate(
    BuildContext pickerContext,
    String currentValue,
  ) async {
    final current = _parseVictimBirthDate(currentValue);
    final reference = _selectedDay;
    final suggestedYear = reference.year - 30;
    final initial = current ??
        DateTime(
          suggestedYear < 1900 ? 1900 : suggestedYear,
          reference.month,
          reference.day,
        );

    return showDatePicker(
      context: pickerContext,
      initialDate: initial.isAfter(reference) ? reference : initial,
      firstDate: DateTime(1900),
      lastDate: reference,
      helpText: 'DATE DE NAISSANCE',
      cancelText: 'ANNULER',
      confirmText: 'VALIDER',
    );
  }

  Widget _victimBirthDateAgeRow({
    required TextEditingController birthDateController,
    required TextEditingController ageController,
    required VoidCallback onBirthDateTap,
  }) {
    final birthDateText = birthDateController.text.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onBirthDateTap,
            child: InputDecorator(
              decoration: _victimInputDecoration(
                'Date de naissance',
                labelFontSize: 11.5,
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ).copyWith(
                suffixIcon: const Icon(
                  Icons.calendar_month_outlined,
                  color: _victimBlue,
                  size: 19,
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
              ),
              child: Text(
                birthDateText.isEmpty ? 'JJ/MM/AAAA' : birthDateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: birthDateText.isEmpty
                      ? _victimBlue.withOpacity(0.55)
                      : _victimBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 62,
          child: InputDecorator(
            decoration: _victimInputDecoration(
              'Age',
              labelFontSize: 12,
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            child: Text(
              ageController.text.trim().isEmpty
                  ? '—'
                  : ageController.text.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _victimBlue,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _hasCompleteInterventionZones(Set<String> selected) {
    final bathingKnown =
        selected.contains('Zone de bain surveillée') ||
        selected.contains('Hors zone de bain surveillée');
    final regulationKnown =
        selected.contains('Zone réglementée') ||
        selected.contains('Hors zone réglementée');
    return bathingKnown && regulationKnown;
  }

  void _toggleInterventionZone(
    Set<String> selected,
    String option,
  ) {
    const opposites = <String, String>{
      'Zone de bain surveillée': 'Hors zone de bain surveillée',
      'Hors zone de bain surveillée': 'Zone de bain surveillée',
      'Zone réglementée': 'Hors zone réglementée',
      'Hors zone réglementée': 'Zone réglementée',
    };

    if (selected.contains(option)) {
      selected.remove(option);
      return;
    }

    selected.remove(opposites[option]);
    selected.add(option);
  }

  Widget _interventionZonesSelector({
    required Set<String> selected,
    required ValueChanged<String> onToggle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF1E3A8A),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ZONE D’INTERVENTION',
            style: TextStyle(
              color: Color(0xFF1E3A8A),
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choisissez la situation de baignade et la situation réglementaire.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _interventionZoneOptions.map((option) {
              final isSelected = selected.contains(option);
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: SizedBox(
                  width: double.infinity,
                  child: FilterChip(
                    selected: isSelected,
                    label: SizedBox(
                      width: double.infinity,
                      child: Text(
                        option,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF1E3A8A),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    selectedColor: const Color(0xFF1E3A8A),
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFF1E3A8A)
                          : const Color(0xFF1E3A8A).withOpacity(0.45),
                    ),
                    onSelected: (_) => onToggle(option),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _entryForm() {
    if (!_canWrite) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF8E24AA),
          width: 1.4,
        ),
      ),
      child: Column(
        children: [
          _presenceSelector(),
          const SizedBox(height: 10),
          SauveteurStyledDropdown(
            labelText: 'Type de fait',
            value: _selectedType,
            options: _types
                .map(
                  (type) => SauveteurDropdownOption(
                    value: type,
                    label: type,
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _selectedType = value);
            },
          ),
          if (_selectedType == 'Intervention') ...[
            const SizedBox(height: 10),
            _interventionZonesSelector(
              selected: _selectedInterventionZones,
              onToggle: (option) {
                setState(() {
                  _toggleInterventionZone(
                    _selectedInterventionZones,
                    option,
                  );
                });
              },
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.58),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFDC2626),
                  width: 1.3,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VICTIME',
                    style: TextStyle(
                      color: _victimBlue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SauveteurStyledDropdown(
                    labelText: 'Sexe',
                    value: _victimSex,
                    valueColor: _victimBlue,
                    options: _victimSexOptions
                        .map(
                          (value) => SauveteurDropdownOption(
                            value: value,
                            label: value,
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _victimSex = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _victimNameController,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: const [
                      _UpperCaseTextFormatter(),
                    ],
                    style: const TextStyle(
                      color: _victimBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _victimInputDecoration(
                      'Nom',
                      suffixIcon: _microphoneButton(
                        'newVictimName',
                        _victimNameController,
                        transform: (value) => value.toUpperCase(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _victimFirstNameController,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [
                      _FirstLetterUpperCaseTextFormatter(),
                    ],
                    style: const TextStyle(
                      color: _victimBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _victimInputDecoration(
                      'Prénom',
                      suffixIcon: _microphoneButton(
                        'newVictimFirstName',
                        _victimFirstNameController,
                        transform: _capitalizeVictimFirstName,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _victimBirthDateAgeRow(
                    birthDateController: _victimBirthDateController,
                    ageController: _victimAgeController,
                    onBirthDateTap: () async {
                      final picked = await _pickVictimBirthDate(
                        context,
                        _victimBirthDateController.text,
                      );
                      if (picked == null || !mounted) return;

                      setState(() {
                        _victimBirthDateController.text =
                            _formatVictimBirthDate(picked);
                        _syncVictimAge(
                          _victimBirthDateController,
                          _victimAgeController,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _victimResidenceController,
                    style: const TextStyle(
                      color: _victimBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _victimInputDecoration(
                      'Lieu d’habitation',
                      suffixIcon: _microphoneButton(
                        'newVictimResidence',
                        _victimResidenceController,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _victimPhoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [
                      _FrenchPhoneInputFormatter(),
                    ],
                    style: const TextStyle(
                      color: _victimBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                    decoration: _victimInputDecoration(
                      'Numéro de téléphone',
                      hintText: '06 12 34 56 78',
                      suffixIcon: _microphoneButton(
                        'newVictimPhone',
                        _victimPhoneController,
                        transform: _formatSpokenFrenchPhone,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SauveteurStyledDropdown(
                    labelText: 'Qualification',
                    value: _victimQualification,
                    valueColor: _victimBlue,
                    options: _victimQualificationOptions
                        .map(
                          (value) => SauveteurDropdownOption(
                            value: value,
                            label: value,
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _victimQualification = value);
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Fait du jour',
              suffixIcon: _microphoneButton(
                'newFact',
                _descriptionController,
              ),
              labelStyle: _fieldLabelStyle,
              floatingLabelStyle: _fieldLabelStyle,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: SauveteurStyledDropdown.borderColor,
                  width: 1.6,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: SauveteurStyledDropdown.borderColor,
                  width: 1.6,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: SauveteurStyledDropdown.borderColor,
                  width: 1.8,
                ),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Information restreinte',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Visible uniquement par le chef de poste et l\'adjoint.',
            ),
            value: _restricted,
            onChanged: (value) => setState(() => _restricted = value),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _addEntry,
              icon: const Icon(Icons.add_task_rounded),
              label: Text(
                _saving ? 'ENREGISTREMENT...' : 'AJOUTER À LA MAIN COURANTE',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8E24AA),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                  Text(
                    'MAIN COURANTE',
                    style: TextStyle(
                      color: widget.profileColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : ListView(
                                        children: [
                                          _selectedDayHeader(),
                                          const SizedBox(height: 10),
                                          if (!_isSphotOn) ...[
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.68),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: const Color(0xFF1E3A8A)
                                                      .withOpacity(0.35),
                                                ),
                                              ),
                                              child: const Text(
                                                'CONSULTATION HISTORIQUE — '
                                                'SPHOT est OFF. Les mains courantes '
                                                'restent consultables en lecture seule.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Color(0xFF1E3A8A),
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 10),
                                          ],
                                          if (_institutionalContacts.isNotEmpty) ...[
                                            _institutionalContactsCard(),
                                            const SizedBox(height: 12),
                                          ],
                                          if (_selectedDayIsToday)
                                            _entryForm()
                                          else if (_canWrite)
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.65),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.black12,
                                                ),
                                              ),
                                              child: const Text(
                                                'Consultation d’une journée passée. '
                                                'Les saisies existantes restent '
                                                'modifiables et supprimables.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          if (_canWrite)
                                            const SizedBox(height: 12),
                                          if (_statusMessage != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              child: Text(
                                                _statusMessage!,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          if (_personnelRows.isNotEmpty) ...[
                                            _personnelCard(),
                                            const SizedBox(height: 12),
                                          ],
                                          _factsSection(),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            height: 46,
                                            child: ElevatedButton.icon(
                                              onPressed:
                                                  _sharingMainCourante
                                                      ? null
                                                      : _shareMainCourante,
                                              icon: _sharingMainCourante
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            Color(0xFF1E3A8A),
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.share_rounded,
                                                      color:
                                                          Color(0xFF1E3A8A),
                                                      size: 20,
                                                    ),
                                              label: const Text(
                                                'PARTAGER',
                                                style: TextStyle(
                                                  color: Color(0xFF1E3A8A),
                                                  fontWeight:
                                                      FontWeight.w900,
                                                ),
                                              ),
                                              style:
                                                  ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                foregroundColor:
                                                    const Color(0xFF1E3A8A),
                                                disabledBackgroundColor:
                                                    Colors.transparent,
                                                elevation: 0,
                                                side: const BorderSide(
                                                  color: Color(0xFF1E3A8A),
                                                  width: 2,
                                                ),
                                                shape:
                                                    RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    14,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                          ),
                          const SizedBox(height: 8),
                          _dayTabs(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.black,
                        size: 21,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = newValue.text.toUpperCase();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty,
    );
  }
}

class _FirstLetterUpperCaseTextFormatter extends TextInputFormatter {
  const _FirstLetterUpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;

    final lower = raw.toLowerCase();
    final formatted = lower[0].toUpperCase() + lower.substring(1);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty,
    );
  }
}

class _FrenchPhoneInputFormatter extends TextInputFormatter {
  const _FrenchPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digits.length > 10 ? digits.substring(0, 10) : digits;
    final groups = <String>[];

    for (var i = 0; i < limited.length; i += 2) {
      final end = (i + 2 < limited.length) ? i + 2 : limited.length;
      groups.add(limited.substring(i, end));
    }

    final formatted = groups.join(' ');

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
