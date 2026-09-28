import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'widgets/sauveteur_styled_dropdown.dart';
import 'package:http/http.dart' as http;

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
  final _actionController = TextEditingController();
  final _dayScrollController = ScrollController();

  final List<Map<String, String>> _spots = [];
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _institutionalContacts = [];

  String? _selectedSpotId;
  String _selectedType = 'Observation';
  late DateTime _selectedDay;
  bool _restricted = false;
  bool _loading = true;
  bool _saving = false;
  bool _entryMutationInProgress = false;
  String? _statusMessage;

  static const _types = <String>[
    'Observation',
    'Incident',
    'Intervention',
    'Secours',
    'Personne recherchée',
    'Danger',
    'Météo exceptionnelle',
    'Matériel',
    'Information administrative',
    'Autre',
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
    });

    _scrollSelectedDayIntoView();
    await _loadEntries();
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = _today;
    _loadSpots();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _actionController.dispose();
    _dayScrollController.dispose();
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

    if (_isSphotOn && _selectedSpotId != null) {
      await _loadEntries();
    }
  }

  Future<void> _loadEntries() async {
    if (!_isSphotOn || _selectedSpotId == null) {
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

      setState(() {
        _entries = raw
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList();
      });
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
          'actionTaken': _actionController.text.trim(),
          'visibility': _restricted ? 'restricted' : 'operational',
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
      _actionController.clear();
      setState(() {
        _restricted = false;
        _selectedType = 'Observation';
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
    bool restricted =
        (entry['visibility'] ?? 'operational').toString() == 'restricted';

    final descriptionController = TextEditingController(
      text: (entry['description'] ?? '').toString(),
    );
    final actionController = TextEditingController(
      text: (entry['actionTaken'] ?? '').toString(),
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        minLines: 3,
                        maxLines: 7,
                        decoration: const InputDecoration(
                          labelText: 'Fait du jour',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: actionController,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Action / suite donnée',
                          border: OutlineInputBorder(),
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

                    Navigator.of(dialogContext).pop({
                      'type': selectedType,
                      'description': description,
                      'actionTaken': actionController.text.trim(),
                      'restricted': restricted,
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
    actionController.dispose();

    if (result == null) return;

    await _updateEntry(
      entry,
      type: (result['type'] ?? 'Observation').toString(),
      description: (result['description'] ?? '').toString(),
      actionTaken: (result['actionTaken'] ?? '').toString(),
      restricted: result['restricted'] == true,
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

  Widget _modeBanner() {
    final color = _isSphotOn
        ? const Color(0xFF15803D)
        : const Color(0xFFDC2626);

    final text = _isSphotOn
        ? _isSupervisor
            ? 'SPHOT ON — lecture et saisie de la main courante autorisées.'
            : 'SPHOT ON — consultation uniquement. La saisie est réservée '
                'au chef de poste et à son adjoint.'
        : 'SPHOT OFF — la main courante réelle est masquée et aucune '
            'action de test ne peut la modifier.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _isSphotOn
            ? const Color(0xFFEAF7EE)
            : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1.25,
        ),
      ),
    );
  }

  Widget _spotSelector() {
    if (_spots.isEmpty) {
      return const Text(
        'Aucun poste de secours affecté.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFFDC2626),
          fontWeight: FontWeight.w800,
        ),
      );
    }

    return SauveteurStyledDropdown(
      labelText: 'Poste de secours',
      value: _selectedSpotId,
      options: _spots
          .map(
            (spot) => SauveteurDropdownOption(
              value: spot['id'] ?? '',
              label: spot['label'] ?? spot['id'] ?? '',
            ),
          )
          .where((option) => option.value.isNotEmpty)
          .toList(),
      onChanged: (value) async {
        setState(() => _selectedSpotId = value);
        await _loadEntries();
      },
    );
  }

  Widget _dayTabs() {
    final today = _today;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
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
          Text(
            '${_months[today.month - 1]} ${today.year}',
            style: const TextStyle(
              color: Color(0xFF1E3A8A),
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
                final day = index + 1;
                final date = DateTime(today.year, today.month, day);
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
                      width: 40,
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
                          fontSize: 12,
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
                        (entry['type'] ?? 'Observation')
                            .toString()
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF8E24AA),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
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
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Fait du jour',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _actionController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Action / suite donnée',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
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
              'Masquée aux sauveteurs ordinaires. Chef et adjoint '
              'conservent l’accès.',
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

  Widget _bottomDayNavigation() {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 100,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.94),
          border: const Border(
            top: BorderSide(
              color: Color(0xFF1E3A8A),
              width: 1.5,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: _dayTabs()),
            const SizedBox(width: 10),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: const Color(0xFF1E3A8A),
                    width: 1.7,
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF1E3A8A),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: _bottomDayNavigation(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                      child: !_isSphotOn
                          ? const Center(
                              child: Text(
                                'La main courante réelle devient accessible '
                                'uniquement lorsque SPHOT est ON.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            )
                          : _loading
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                              : ListView(
                                  children: [
                                    _selectedDayHeader(),
                                    const SizedBox(height: 10),
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
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: Text(
                                          _statusMessage!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    if (_entries.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(18),
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
        ],
      ),
    );
  }
}
