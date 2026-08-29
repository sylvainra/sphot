import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/advertising_pricing_config.dart';
import '../../shared/web_colors.dart';
import '../models/advertising_visual_data.dart';
import '../models/diffusion_preview_data.dart';

class DiffusionSection extends StatefulWidget {
  const DiffusionSection({
    super.key,
    required this.user,
    required this.advertisingPosition,
    required this.advertisingVisual,
    required this.initialPreview,
    required this.onPreviewChanged,
  });

  final User? user;
  final LatLng? advertisingPosition;
  final AdvertisingVisualData advertisingVisual;
  final DiffusionPreviewData initialPreview;
  final ValueChanged<DiffusionPreviewData> onPreviewChanged;

  @override
  State<DiffusionSection> createState() => _DiffusionSectionState();
}

class _DiffusionSectionState extends State<DiffusionSection> {
  static const _radiusChoices = AdvertisingPricingConfig.radiusChoices;
  static const _options = <_DiffusionOption>[
    _DiffusionOption(
      value: 'map',
      label: 'CARTE SPHOT',
      description: 'Votre publicité apparaît pendant la navigation sur la carte principale.',
      icon: Icons.map_outlined,
    ),
    _DiffusionOption(
      value: 'premium',
      label: 'FICHE SPHOT PREMIUM',
      description: 'Votre publicité apparaît sur la fiche détaillée des SPHOTS concernés.',
      usesFireIcon: true,
    ),
    _DiffusionOption(
      value: 'pack',
      label: 'PACK VISIBILITÉ TOTALE',
      description: 'Votre publicité est présente à la fois sur la carte et sur les fiches SPHOTS.',
      icon: Icons.stars_outlined,
      recommended: true,
    ),
  ];

  bool _loading = true;
  bool _saving = false;
  bool _completed = false;
  bool _requestExists = false;
  String? _selectedValue;
  double _radiusKm = 0.5;
  String? _savedBannerUrl;
  String _advertiserName = '';
  String? _logoUrl;
  double? _savedLatitude;
  double? _savedLongitude;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedValue = _valueForPreviewType(widget.initialPreview.type);
    _radiusKm = widget.initialPreview.radiusKm;
    _initialiseDiffusion();
  }

  @override
  void didUpdateWidget(covariant DiffusionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final positionIsUnchanged =
        oldWidget.advertisingPosition == widget.advertisingPosition;
    final visualIsUnchanged =
        oldWidget.advertisingVisual.bytes == widget.advertisingVisual.bytes &&
        oldWidget.advertisingVisual.url == widget.advertisingVisual.url;
    if (positionIsUnchanged && visualIsUnchanged) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyPreview();
    });
  }

  Future<void> _initialiseDiffusion() async {
    final user = widget.user;
    if (user != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(user.uid)
            .get();
        final data = snapshot.data();
        _requestExists = snapshot.exists;

        if (data != null) {
          final diffusion = _map(data['diffusion']);
          final establishment = _map(data['establishment']);
          final advertisingSpot = _map(data['advertisingSpot']);
          final savedValue = diffusion['visibilityType']?.toString();
          if (_options.any((option) => option.value == savedValue)) {
            _selectedValue = savedValue;
          }
          final savedRadius = _toDouble(diffusion['radiusKm']);
          if (savedRadius != null && _radiusChoices.contains(savedRadius)) {
            _radiusKm = savedRadius;
          }
          _savedBannerUrl = _nullableText(
            advertisingSpot['bannerUrl'] ?? diffusion['bannerUrl'],
          );
          _advertiserName = _text(
            establishment['businessName'],
            data['advertiserName'],
          );
          _logoUrl = _nullableText(establishment['logoUrl'] ?? data['logoUrl']);
          _savedLatitude = _toDouble(advertisingSpot['latitude']);
          _savedLongitude = _toDouble(advertisingSpot['longitude']);
          _completed =
              data['diffusionCompleted'] == true &&
              _selectedValue != null &&
              _visualIsAvailable;
        }
      } catch (error) {
        _error = 'Impossible de charger la diffusion enregistrée.';
        debugPrint('Chargement diffusion annonceur impossible : $error');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyPreview();
    });
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  String _text(Object? primary, [Object? fallback]) {
    final value = primary?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
    return fallback?.toString().trim() ?? '';
  }

  String? _nullableText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  DiffusionPreviewType? get _previewType {
    return switch (_selectedValue) {
      'map' => DiffusionPreviewType.map,
      'premium' => DiffusionPreviewType.premium,
      'pack' => DiffusionPreviewType.pack,
      _ => null,
    };
  }

  String? _valueForPreviewType(DiffusionPreviewType? type) {
    return switch (type) {
      DiffusionPreviewType.map => 'map',
      DiffusionPreviewType.premium => 'premium',
      DiffusionPreviewType.pack => 'pack',
      null => null,
    };
  }

  void _notifyPreview() {
    final position = widget.advertisingPosition;
    final visual = widget.advertisingVisual;
    widget.onPreviewChanged(
      DiffusionPreviewData(
        type: _previewType,
        bannerBytes: visual.bytes,
        bannerUrl: visual.url ?? _savedBannerUrl,
        advertiserName: _advertiserName,
        logoUrl: _logoUrl,
        latitude: position?.latitude ?? _savedLatitude,
        longitude: position?.longitude ?? _savedLongitude,
        radiusKm: _radiusKm,
      ),
    );
  }

  bool get _visualIsAvailable {
    return widget.advertisingVisual.isAvailable || _savedBannerUrl != null;
  }

  void _select(String value) {
    setState(() {
      _selectedValue = value;
      _completed = false;
      _error = null;
    });
    _notifyPreview();
  }

  void _selectRadius(double radius) {
    setState(() {
      _radiusKm = radius;
      _completed = false;
      _error = null;
    });
    _notifyPreview();
  }

  Future<void> _save() async {
    final selectedValue = _selectedValue;
    if (selectedValue == null) {
      setState(() {
        _error = 'Sélectionnez un type de visibilité.';
      });
      return;
    }
    if (!_visualIsAvailable) {
      setState(() {
        _error = 'Ajoutez le visuel publicitaire à l’étape 3.';
      });
      return;
    }

    final selectedOption = _options.firstWhere(
      (option) => option.value == selectedValue,
    );

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = widget.user;
      if (user != null) {
        final creationData = _requestExists
            ? <String, Object?>{}
            : <String, Object?>{
                'status': 'pending',
                'createdAt': FieldValue.serverTimestamp(),
              };

        await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(user.uid)
            .set({
              ...creationData,
              'uid': user.uid,
              'diffusionCompleted': true,
              'diffusion': <String, Object?>{
                'visibilityType': selectedOption.value,
                'visibilityLabel': selectedOption.label,
                'radiusKm': _radiusKm,
                'confirmedAt': FieldValue.serverTimestamp(),
              },
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        _requestExists = true;
      }

      if (!mounted) return;
      setState(() => _completed = true);
      _notifyPreview();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'L’enregistrement a échoué. Réessayez.');
      debugPrint('Enregistrement diffusion annonceur impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: WebColors.red)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    color: WebColors.blue,
                    size: 30,
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TYPE DE VISIBILITÉ',
                          style: TextStyle(
                            color: WebColors.blue,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'SÉLECTIONNEZ UNE OFFRE',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ..._options.map(
                (option) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _VisibilityOptionCard(
                    option: option,
                    selected: option.value == _selectedValue,
                    onTap: () => _select(option.value),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildRadiusCard(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _completed ? WebColors.red : WebColors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
                    _completed
                        ? Icons.check_circle_outline_rounded
                        : Icons.save_outlined,
                  ),
            label: Text(
              _saving
                  ? 'ENREGISTREMENT…'
                  : _completed
                  ? 'DIFFUSION ENREGISTRÉE'
                  : 'ENREGISTRER LA DIFFUSION',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRadiusCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.radar_rounded, color: WebColors.blue, size: 30),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RAYON D’ACTION',
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'AUTOUR DE VOTRE SPHOT PUBLICITAIRE',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _radiusChoices.map((radius) {
              final selected = _radiusKm == radius;
              return OutlinedButton(
                onPressed: () => _selectRadius(radius),
                style: OutlinedButton.styleFrom(
                  foregroundColor: selected ? WebColors.red : WebColors.blue,
                  backgroundColor: selected
                      ? WebColors.red.withOpacity(0.045)
                      : Colors.white,
                  side: BorderSide(
                    color: selected ? WebColors.red : WebColors.blue,
                    width: selected ? 2 : 1.3,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: Text(
                  AdvertisingPricingConfig.radiusLabel(radius),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _VisibilityOptionCard extends StatelessWidget {
  const _VisibilityOptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _DiffusionOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = selected ? WebColors.red : WebColors.blue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? WebColors.red.withOpacity(0.045)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: accentColor, width: selected ? 2 : 1.3),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                height: 36,
                child: option.usesFireIcon
                    ? SvgPicture.asset(
                        selected
                            ? 'data/icons/fire_red_icon.svg'
                            : 'data/icons/fire_blue_icon.svg',
                        width: 30,
                        height: 30,
                        fit: BoxFit.contain,
                      )
                    : Icon(option.icon, color: accentColor, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (option.recommended)
                      Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: WebColors.red,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'RECOMMANDÉ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    Text(
                      option.label,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      option.description,
                      style: const TextStyle(
                        color: Color(0xFF4B5F97),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: accentColor,
                size: 25,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffusionOption {
  const _DiffusionOption({
    required this.value,
    required this.label,
    required this.description,
    this.icon,
    this.usesFireIcon = false,
    this.recommended = false,
  });

  final String value;
  final String label;
  final String description;
  final IconData? icon;
  final bool usesFireIcon;
  final bool recommended;
}
