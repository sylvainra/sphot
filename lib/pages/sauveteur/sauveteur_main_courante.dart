import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SauveteurMainCourantePage extends StatefulWidget {
  final Color profileColor;
  final String userRole;
  final String territoireId;
  final String login;
  final String sphotMode;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;

  const SauveteurMainCourantePage({
    super.key,
    required this.profileColor,
    required this.userRole,
    required this.territoireId,
    required this.login,
    required this.sphotMode,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
  });

  @override
  State<SauveteurMainCourantePage> createState() =>
      _SauveteurMainCourantePageState();
}

class _SauveteurMainCourantePageState
    extends State<SauveteurMainCourantePage> {
  final _descriptionController = TextEditingController();
  final _actionController = TextEditingController();

  final List<Map<String, String>> _spots = [];
  List<Map<String, dynamic>> _entries = [];

  String? _selectedSpotId;
  String _selectedType = 'Observation';
  bool _restricted = false;
  bool _loading = true;
  bool _saving = false;
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

  bool get _isSphotOn => widget.sphotMode.toUpperCase() == 'ON';

  bool get _isSupervisor {
    final role = widget.userRole.trim().toLowerCase();
    return role == 'chef de poste' || role == 'adjoint chef de poste';
  }

  bool get _canWrite => _isSphotOn && _isSupervisor;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  Future<void> _loadSpots() async {
    final assigned = widget.postesAffectes.toSet();
    final snapshot = await FirebaseFirestore.instance
        .collection('territoires')
        .doc(widget.territoireId)
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
      _selectedSpotId = _spots.isEmpty ? null : _spots.first['id'];
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

    return DropdownButtonFormField<String>(
      value: _selectedSpotId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Poste de secours',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      items: _spots
          .map(
            (spot) => DropdownMenuItem<String>(
              value: spot['id'],
              child: Text(
                spot['label']!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          )
          .toList(),
      onChanged: (value) async {
        setState(() => _selectedSpotId = value);
        await _loadEntries();
      },
    );
  }

  Widget _entryCard(Map<String, dynamic> entry) {
    final createdBy = entry['createdBy'] is Map
        ? Map<String, dynamic>.from(entry['createdBy'] as Map)
        : <String, dynamic>{};
    final role = (createdBy['role'] ?? '').toString();
    final visibility = (entry['visibility'] ?? 'operational').toString();

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
                    if (visibility == 'restricted')
                      const Text(
                        'RESTREINT',
                        style: TextStyle(
                          color: Color(0xFF7E22CE),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
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
          DropdownButtonFormField<String>(
            value: _selectedType,
            decoration: InputDecoration(
              labelText: 'Type de fait',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: _types
                .map(
                  (type) => DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedType = value);
              }
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
                  const SizedBox(height: 6),
                  _modeBanner(),
                  const SizedBox(height: 8),
                  _spotSelector(),
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
                                    _entryForm(),
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
                                          'Aucun fait du jour enregistré.',
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
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 22,
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
