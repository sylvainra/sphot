import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/advertising_pricing_config.dart';

class SuperAdminAdsPage extends StatefulWidget {
  const SuperAdminAdsPage({super.key});

  @override
  State<SuperAdminAdsPage> createState() => _SuperAdminAdsPageState();
}

class _SuperAdminAdsPageState extends State<SuperAdminAdsPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  int _selectedTab = 0;

  String _text(dynamic value) => (value ?? '').toString();

  num _number(dynamic value) {
    if (value is num) return value;
    return num.tryParse(_text(value).replaceAll(',', '.')) ?? 0;
  }

  String _formatDate(dynamic value) {
    if (value == null) return '—';

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is String && value.trim().isNotEmpty) {
      date = DateTime.tryParse(value);
    }

    if (date == null) return '—';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'disabled':
        return Colors.orange;
      case 'reported':
        return redColor;
      case 'deleted':
        return Colors.grey;
      default:
        return adminColor;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'ACTIVE';
      case 'disabled':
        return 'DÉSACTIVÉE';
      case 'reported':
        return 'SIGNALÉE';
      case 'deleted':
        return 'SUPPRIMÉE';
      default:
        return status.isEmpty ? 'INCONNU' : status.toUpperCase();
    }
  }

  Future<void> _updateStatus(
    String docId,
    String status, {
    String? reason,
  }) async {
    await FirebaseFirestore.instance.collection('adRequests').doc(docId).update(
      {
        'status': status,
        'disabledReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> _deleteAd(String docId) async {
    await FirebaseFirestore.instance.collection('adRequests').doc(docId).update(
      {'status': 'deleted', 'updatedAt': FieldValue.serverTimestamp()},
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _selectedTab == index;

    return OutlinedButton(
      onPressed: () {
        setState(() {
          _selectedTab = index;
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? adminColor : Colors.transparent,
        foregroundColor: selected ? Colors.white : adminColor,
        side: const BorderSide(color: adminColor, width: 1.5),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }

  Widget _collectionList({
    required String emptyText,
    required bool Function(Map<String, dynamic> data) filter,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('adRequests').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Erreur de chargement.',
              style: TextStyle(color: redColor, fontWeight: FontWeight.w800),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.where((doc) {
          return filter(doc.data());
        }).toList();

        docs.sort((a, b) {
          final left = a.data()['createdAt'];
          final right = b.data()['createdAt'];

          if (left is Timestamp && right is Timestamp) {
            return right.compareTo(left);
          }

          return 0;
        });

        if (docs.isEmpty) {
          return Center(
            child: Text(
              emptyText,
              style: const TextStyle(
                color: adminColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(top: 4),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();

            final status = _text(data['status']);
            final bannerUrl = _text(data['bannerUrl']);
            final broadcastType = _text(data['broadcastType']);

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _statusColor(status), width: 2),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 170,
                    height: 85,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: adminColor, width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: bannerUrl.isEmpty
                          ? const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: adminColor,
                                size: 36,
                              ),
                            )
                          : Image.network(
                              bannerUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: redColor,
                                    size: 36,
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _text(data['advertiserName']).isEmpty
                              ? 'Annonceur inconnu'
                              : _text(data['advertiserName']).toUpperCase(),
                          style: const TextStyle(
                            color: adminColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Contact : ${_text(data['contactName'])} • ${_text(data['email'])} • ${_text(data['phone'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Site : ${_text(data['websiteUrl']).isEmpty ? '—' : _text(data['websiteUrl'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'SIREN : ${_text(data['siren'])} • SIRET : ${_text(data['siret'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Catégorie : ${_text(data['categoryLabel'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Visibilité : ${_text(data['visibilityLabel'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          broadcastType == 'national'
                              ? 'Zone : Diffusion nationale'
                              : 'Zone : ${_text(data['centerCity']).isEmpty ? 'Localisation carte' : _text(data['centerCity'])} • ${AdvertisingPricingConfig.radiusLabel(_number(data['radiusKm']))}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Diffusion : ${_formatDate(data['campaignStartDate'])} → ${_formatDate(data['campaignEndDate'])} • ${_text(data['durationLabel'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Montant : ${_text(data['totalPriceExclTax'])} € HT',
                          style: const TextStyle(
                            color: redColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (_text(data['message']).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Message : ${_text(data['message'])}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (status != 'active')
                        OutlinedButton.icon(
                          onPressed: () => _updateStatus(doc.id, 'active'),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('RÉACTIVER'),
                        ),
                      if (status == 'active')
                        OutlinedButton.icon(
                          onPressed: () => _updateStatus(
                            doc.id,
                            'disabled',
                            reason: 'Désactivée par Super Admin',
                          ),
                          icon: const Icon(Icons.pause_rounded),
                          label: const Text('DÉSACTIVER'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _updateStatus(doc.id, 'reported'),
                        icon: const Icon(Icons.report_outlined),
                        label: const Text('SIGNALER'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _deleteAd(doc.id),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('SUPPRIMER'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _selectedContent() {
    switch (_selectedTab) {
      case 0:
        return _collectionList(
          emptyText: 'Aucune publicité pour le moment.',
          filter: (data) => _text(data['status']) != 'deleted',
        );
      case 1:
        return _collectionList(
          emptyText: 'Aucune publicité active.',
          filter: (data) => _text(data['status']) == 'active',
        );
      case 2:
        return _collectionList(
          emptyText: 'Aucune publicité désactivée.',
          filter: (data) => _text(data['status']) == 'disabled',
        );
      case 3:
        return _collectionList(
          emptyText: 'Aucune publicité signalée.',
          filter: (data) => _text(data['status']) == 'reported',
        );
      case 4:
        return const _AdvertisingPricingEditor();
      default:
        return _collectionList(
          emptyText: 'Aucune publicité pour le moment.',
          filter: (data) => _text(data['status']) != 'deleted',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Text(
            'PUBLICITÉS SPHOT',
            style: TextStyle(
              color: adminColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tabButton('TOUTES', 0),
              _tabButton('ACTIVES', 1),
              _tabButton('DÉSACTIVÉES', 2),
              _tabButton('SIGNALÉES', 3),
              _tabButton('TARIFICATION', 4),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _selectedContent()),
        ],
      ),
    );
  }
}

class _AdvertisingPricingEditor extends StatefulWidget {
  const _AdvertisingPricingEditor();

  @override
  State<_AdvertisingPricingEditor> createState() =>
      _AdvertisingPricingEditorState();
}

class _AdvertisingPricingEditorState extends State<_AdvertisingPricingEditor> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);

  final Map<String, TextEditingController> _controllers = {};
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fieldKey(String section, String key, [String? parent]) {
    return parent == null ? '$section|$key' : '$section|$parent|$key';
  }

  num _numberAt(Map<String, dynamic> data, List<String> path, num fallback) {
    Object? value = data;
    for (final part in path) {
      if (value is! Map || !value.containsKey(part)) return fallback;
      value = value[part];
    }
    return value is num ? value : fallback;
  }

  String _numberText(num value) {
    final doubleValue = value.toDouble();
    return doubleValue == doubleValue.roundToDouble()
        ? doubleValue.toInt().toString()
        : doubleValue.toString();
  }

  void _setController(String key, num value) {
    _controllers[key] = TextEditingController(text: _numberText(value));
  }

  Future<void> _load() async {
    final defaults = AdvertisingPricingConfig.defaults();
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('advertisingPricing')
          .get();
      final data = snapshot.data() ?? <String, dynamic>{};

      for (final duration in AdvertisingPricingConfig.durations) {
        _setController(
          _fieldKey('basePrices', duration),
          _numberAt(data, [
            'basePrices',
            duration,
          ], defaults['basePrices'][duration] as num),
        );
      }

      for (final visibility in AdvertisingPricingConfig.visibilityLabels.keys) {
        _setController(
          _fieldKey('visibilityMultipliers', visibility),
          _numberAt(data, [
            'visibilityMultipliers',
            visibility,
          ], defaults['visibilityMultipliers'][visibility] as num),
        );
      }

      for (final radius in AdvertisingPricingConfig.radiusChoices) {
        final radiusKey = AdvertisingPricingConfig.radiusKey(radius);
        _setController(
          _fieldKey('radiusMultipliers', radiusKey),
          _numberAt(data, [
            'radiusMultipliers',
            radiusKey,
          ], defaults['radiusMultipliers'][radiusKey] as num),
        );
      }

      for (final visibility in AdvertisingPricingConfig.visibilityLabels.keys) {
        for (final duration in AdvertisingPricingConfig.durations) {
          _setController(
            _fieldKey('nationalFlatPrices', duration, visibility),
            _numberAt(data, [
              'nationalFlatPrices',
              visibility,
              duration,
            ], defaults['nationalFlatPrices'][visibility][duration] as num),
          );
        }
      }
    } catch (error) {
      _error = 'Impossible de charger la tarification publicitaire.';
      debugPrint('Chargement tarification publicitaire impossible : $error');
      for (final duration in AdvertisingPricingConfig.durations) {
        _setController(
          _fieldKey('basePrices', duration),
          defaults['basePrices'][duration] as num,
        );
      }
      for (final visibility in AdvertisingPricingConfig.visibilityLabels.keys) {
        _setController(
          _fieldKey('visibilityMultipliers', visibility),
          defaults['visibilityMultipliers'][visibility] as num,
        );
      }
      for (final radius in AdvertisingPricingConfig.radiusChoices) {
        final radiusKey = AdvertisingPricingConfig.radiusKey(radius);
        _setController(
          _fieldKey('radiusMultipliers', radiusKey),
          defaults['radiusMultipliers'][radiusKey] as num,
        );
      }
      for (final visibility in AdvertisingPricingConfig.visibilityLabels.keys) {
        for (final duration in AdvertisingPricingConfig.durations) {
          _setController(
            _fieldKey('nationalFlatPrices', duration, visibility),
            defaults['nationalFlatPrices'][visibility][duration] as num,
          );
        }
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  double? _value(String key) {
    return double.tryParse(_controllers[key]!.text.trim().replaceAll(',', '.'));
  }

  Future<void> _save() async {
    final values = <String, double>{};
    for (final entry in _controllers.entries) {
      final value = _value(entry.key);
      if (value == null || value <= 0) {
        setState(() {
          _saved = false;
          _error =
              'Tous les tarifs et coefficients doivent être supérieurs à zéro.';
        });
        return;
      }
      values[entry.key] = value;
    }

    final basePrices = <String, double>{};
    for (final duration in AdvertisingPricingConfig.durations) {
      basePrices[duration] = values[_fieldKey('basePrices', duration)]!;
    }

    final visibilityMultipliers = <String, double>{};
    for (final visibility in AdvertisingPricingConfig.visibilityLabels.keys) {
      visibilityMultipliers[visibility] =
          values[_fieldKey('visibilityMultipliers', visibility)]!;
    }

    final radiusMultipliers = <String, double>{};
    for (final radius in AdvertisingPricingConfig.radiusChoices) {
      final radiusKey = AdvertisingPricingConfig.radiusKey(radius);
      radiusMultipliers[radiusKey] =
          values[_fieldKey('radiusMultipliers', radiusKey)]!;
    }

    final nationalFlatPrices = <String, Map<String, double>>{};
    for (final visibility in AdvertisingPricingConfig.visibilityLabels.keys) {
      nationalFlatPrices[visibility] = <String, double>{};
      for (final duration in AdvertisingPricingConfig.durations) {
        nationalFlatPrices[visibility]![duration] =
            values[_fieldKey('nationalFlatPrices', duration, visibility)]!;
      }
    }

    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('advertisingPricing')
          .set({
            'basePrices': basePrices,
            'visibilityMultipliers': visibilityMultipliers,
            'radiusMultipliers': radiusMultipliers,
            'nationalFlatPrices': nationalFlatPrices,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'L’enregistrement des tarifs a échoué.');
      debugPrint(
        'Enregistrement tarification publicitaire impossible : $error',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {required String suffix}) {
    return SizedBox(
      width: 190,
      child: TextField(
        controller: _controllers[key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) {
          if (_saved || _error != null) {
            setState(() {
              _saved = false;
              _error = null;
            });
          }
        },
        style: const TextStyle(color: _blue, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _group({
    required String title,
    required String subtitle,
    required List<Widget> fields,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _blue, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _blue,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, children: fields),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _red));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
      children: [
        const Text(
          'TARIFICATION PUBLICITAIRE',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _blue,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ces coefficients sont internes et ne sont jamais affichés aux annonceurs.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _group(
          title: 'TARIFS DE BASE LOCAUX',
          subtitle: 'Montants HT avant application des coefficients.',
          fields: AdvertisingPricingConfig.durations
              .map(
                (duration) => _field(
                  _fieldKey('basePrices', duration),
                  duration,
                  suffix: '€ HT',
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        _group(
          title: 'COEFFICIENTS DE VISIBILITÉ',
          subtitle: 'Réservés au calcul interne SPHOT.',
          fields: AdvertisingPricingConfig.visibilityLabels.entries
              .map(
                (entry) => _field(
                  _fieldKey('visibilityMultipliers', entry.key),
                  entry.value,
                  suffix: '×',
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        _group(
          title: 'COEFFICIENTS DE RAYON',
          subtitle:
              'Grille exclusive : SPHOT ONLY, 50 m, 100 m, 150 m et 200 m.',
          fields: AdvertisingPricingConfig.radiusChoices.map((radius) {
            final radiusKey = AdvertisingPricingConfig.radiusKey(radius);
            return _field(
              _fieldKey('radiusMultipliers', radiusKey),
              AdvertisingPricingConfig.radiusLabel(radius),
              suffix: '×',
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        ...AdvertisingPricingConfig.visibilityLabels.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _group(
              title: 'FORFAITS NATIONAUX — ${entry.value}',
              subtitle: 'Montants forfaitaires HT sans coefficient de rayon.',
              fields: AdvertisingPricingConfig.durations
                  .map(
                    (duration) => _field(
                      _fieldKey('nationalFlatPrices', duration, entry.key),
                      duration,
                      suffix: '€ HT',
                    ),
                  )
                  .toList(),
            ),
          );
        }),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _red, fontWeight: FontWeight.w900),
            ),
          ),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _saved ? _red : _blue,
              foregroundColor: Colors.white,
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    _saved ? Icons.check_circle_outline : Icons.save_outlined,
                  ),
            label: Text(
              _saving
                  ? 'ENREGISTREMENT…'
                  : _saved
                  ? 'TARIFS ENREGISTRÉS'
                  : 'ENREGISTRER LES TARIFS',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
