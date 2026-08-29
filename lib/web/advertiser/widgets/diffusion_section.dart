import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/web_colors.dart';
import '../models/diffusion_preview_data.dart';

class DiffusionSection extends StatefulWidget {
  const DiffusionSection({
    super.key,
    required this.user,
    required this.advertisingPosition,
    required this.onPreviewChanged,
  });

  final User? user;
  final LatLng? advertisingPosition;
  final ValueChanged<DiffusionPreviewData> onPreviewChanged;

  @override
  State<DiffusionSection> createState() => _DiffusionSectionState();
}

class _DiffusionSectionState extends State<DiffusionSection> {
  static const _options = <_DiffusionOption>[
    _DiffusionOption(
      value: 'map',
      label: 'CARTE SPHOT',
      description:
          'Votre publicité apparaît pendant la navigation sur la carte principale.',
      icon: Icons.map_outlined,
    ),
    _DiffusionOption(
      value: 'premium',
      label: 'FICHE SPHOT PREMIUM',
      description:
          'Votre publicité apparaît sur la fiche détaillée des SPHOTS concernés.',
      usesFireIcon: true,
    ),
    _DiffusionOption(
      value: 'pack',
      label: 'PACK VISIBILITÉ TOTALE',
      description:
          'Votre publicité est présente à la fois sur la carte et sur les fiches SPHOTS.',
      icon: Icons.stars_outlined,
      recommended: true,
    ),
  ];

  bool _loading = true;
  bool _saving = false;
  bool _completed = false;
  bool _requestExists = false;
  String? _selectedValue;
  Uint8List? _bannerBytes;
  String? _bannerUrl;
  String? _bannerFileName;
  String? _bannerExtension;
  String? _bannerMimeType;
  int? _bannerFileSizeBytes;
  int? _bannerWidth;
  int? _bannerHeight;
  String _advertiserName = '';
  String? _logoUrl;
  double? _savedLatitude;
  double? _savedLongitude;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialiseDiffusion();
  }

  @override
  void didUpdateWidget(covariant DiffusionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.advertisingPosition == widget.advertisingPosition) return;
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
          _bannerUrl = _nullableText(diffusion['bannerUrl']);
          _bannerFileName = _nullableText(diffusion['bannerFileName']);
          _bannerWidth = _toInt(diffusion['bannerWidth']);
          _bannerHeight = _toInt(diffusion['bannerHeight']);
          _bannerFileSizeBytes = _toInt(diffusion['bannerFileSizeBytes']);
          _advertiserName = _text(
            establishment['businessName'],
            data['advertiserName'],
          );
          _logoUrl = _nullableText(
            establishment['logoUrl'] ?? data['logoUrl'],
          );
          _savedLatitude = _toDouble(advertisingSpot['latitude']);
          _savedLongitude = _toDouble(advertisingSpot['longitude']);
          _completed =
              data['diffusionCompleted'] == true &&
              _selectedValue != null &&
              _bannerUrl != null;
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

  int? _toInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
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

  void _notifyPreview() {
    final position = widget.advertisingPosition;
    widget.onPreviewChanged(
      DiffusionPreviewData(
        type: _previewType,
        bannerBytes: _bannerBytes,
        bannerUrl: _bannerUrl,
        advertiserName: _advertiserName,
        logoUrl: _logoUrl,
        latitude: position?.latitude ?? _savedLatitude,
        longitude: position?.longitude ?? _savedLongitude,
      ),
    );
  }

  void _select(String value) {
    setState(() {
      _selectedValue = value;
      _completed = false;
      _error = null;
    });
    _notifyPreview();
  }

  Future<void> _pickBanner() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final fileName = picked.name;
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    const allowedExtensions = {'png', 'jpg', 'jpeg', 'webp'};

    if (!allowedExtensions.contains(extension)) {
      setState(() {
        _error = 'Format refusé. Utilisez PNG, JPG ou WEBP.';
      });
      return;
    }

    final image = await decodeImageFromList(bytes);
    final mimeType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    setState(() {
      _bannerBytes = bytes;
      _bannerFileName = fileName;
      _bannerExtension = extension;
      _bannerMimeType = mimeType;
      _bannerFileSizeBytes = bytes.length;
      _bannerWidth = image.width;
      _bannerHeight = image.height;
      _completed = false;
      _error = null;
    });
    _notifyPreview();
  }

  bool get _bannerIsValid {
    final width = _bannerWidth;
    final height = _bannerHeight;
    final fileSize = _bannerFileSizeBytes;
    if (_bannerUrl != null && _bannerBytes == null) return true;
    if (width == null || height == null || fileSize == null) return false;
    if (fileSize > 2 * 1024 * 1024) return false;
    if (width < 900 || height < 450) return false;
    if (width > 2400 || height > 1200) return false;
    final ratio = width / height;
    return ratio >= 1.85 && ratio <= 2.15;
  }

  String get _bannerQualityMessage {
    if (_bannerBytes == null && _bannerUrl == null) {
      return 'Ajoutez votre visuel pour obtenir un aperçu réel.';
    }
    if (_bannerBytes == null && _bannerUrl != null) {
      return 'Visuel publicitaire enregistré.';
    }
    if (_bannerFileSizeBytes != null &&
        _bannerFileSizeBytes! > 2 * 1024 * 1024) {
      return 'Visuel non conforme : 2 Mo maximum.';
    }
    if (_bannerWidth == null || _bannerHeight == null) return '';
    if (!_bannerIsValid) {
      return 'Visuel non conforme : utilisez un format proche de 1200 × 600 px.';
    }
    if (_bannerWidth == 1200 && _bannerHeight == 600) {
      return 'Visuel conforme SPHOT : 1200 × 600 px.';
    }
    return 'Visuel compatible SPHOT : $_bannerWidth × $_bannerHeight px.';
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} Mo';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} Ko';
  }

  Future<String?> _uploadBanner(String uid) async {
    final bytes = _bannerBytes;
    if (bytes == null) return _bannerUrl;

    final extension = _bannerExtension ?? 'jpg';
    final reference = FirebaseStorage.instance
        .ref()
        .child('advertising_banners')
        .child(uid)
        .child('banner_${DateTime.now().millisecondsSinceEpoch}.$extension');

    await reference.putData(
      bytes,
      SettableMetadata(contentType: _bannerMimeType ?? 'image/jpeg'),
    );
    return reference.getDownloadURL();
  }

  Future<void> _save() async {
    final selectedValue = _selectedValue;
    if (selectedValue == null) {
      setState(() {
        _error = 'Sélectionnez un type de visibilité.';
      });
      return;
    }
    if (!_bannerIsValid) {
      setState(() {
        _error = 'Ajoutez un visuel publicitaire conforme avant d’enregistrer.';
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
      var bannerUrl = _bannerUrl;
      if (user != null) {
        bannerUrl = await _uploadBanner(user.uid);
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
            'bannerUrl': bannerUrl,
            'bannerFileName': _bannerFileName,
            'bannerMimeType': _bannerMimeType,
            'bannerFileSizeBytes': _bannerFileSizeBytes,
            'bannerWidth': _bannerWidth,
            'bannerHeight': _bannerHeight,
            'confirmedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _requestExists = true;
      }

      if (!mounted) return;
      setState(() {
        _bannerUrl = bannerUrl;
        if (user != null) _bannerBytes = null;
        _completed = true;
      });
      _notifyPreview();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diffusion enregistrée.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'L’enregistrement a échoué. Réessayez.');
      debugPrint('Enregistrement diffusion annonceur impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildBannerCard() {
    final hasBanner = _bannerBytes != null || _bannerUrl != null;
    final qualityColor = _bannerIsValid
        ? WebColors.blue
        : hasBanner
            ? WebColors.red
            : const Color(0xFF6B7280);

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
              Icon(
                Icons.image_outlined,
                color: WebColors.blue,
                size: 30,
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VISUEL PUBLICITAIRE',
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'FORMAT RECOMMANDÉ : 1200 × 600 PX',
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
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickBanner,
            style: OutlinedButton.styleFrom(
              foregroundColor: WebColors.blue,
              side: const BorderSide(color: WebColors.blue, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(
              hasBanner ? 'REMPLACER LE VISUEL' : 'AJOUTER LE VISUEL',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'PNG, JPG ou WEBP • 2 Mo maximum',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF4B5F97),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_bannerFileName != null) ...[
            const SizedBox(height: 10),
            Text(
              _bannerFileName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WebColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_bannerFileSizeBytes != null)
              Text(
                _formatFileSize(_bannerFileSizeBytes),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WebColors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
          const SizedBox(height: 9),
          Text(
            _bannerQualityMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: qualityColor,
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: WebColors.red),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBannerCard(),
        const SizedBox(height: 14),
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
            border: Border.all(
              color: accentColor,
              width: selected ? 2 : 1.3,
            ),
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
                    : Icon(
                        option.icon,
                        color: accentColor,
                        size: 30,
                      ),
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
