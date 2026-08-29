import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/advertising_pricing_config.dart';
import '../../shared/web_colors.dart';
import '../models/advertising_visual_data.dart';

class AdvertisingSpotSection extends StatefulWidget {
  const AdvertisingSpotSection({
    super.key,
    required this.user,
    required this.position,
    required this.initialVisual,
    required this.initialRadiusKm,
    required this.startingPriceExclTax,
    required this.onPositionChanged,
    required this.onVisualChanged,
    required this.onRadiusChanged,
  });

  final User? user;
  final LatLng? position;
  final AdvertisingVisualData initialVisual;
  final double initialRadiusKm;
  final int startingPriceExclTax;
  final void Function(LatLng point, {required bool centerMap})
  onPositionChanged;
  final ValueChanged<AdvertisingVisualData> onVisualChanged;
  final ValueChanged<double> onRadiusChanged;

  @override
  State<AdvertisingSpotSection> createState() => _AdvertisingSpotSectionState();
}

class _AdvertisingSpotSectionState extends State<AdvertisingSpotSection> {
  bool _loading = true;
  bool _saving = false;
  bool _completed = false;
  bool _requestExists = false;
  bool _loadingSavedPosition = false;
  double _radiusKm = 0;
  Uint8List? _bannerBytes;
  String? _bannerUrl;
  String? _bannerFileName;
  String? _bannerExtension;
  String? _bannerMimeType;
  int? _bannerFileSizeBytes;
  int? _bannerWidth;
  int? _bannerHeight;
  String? _error;

  @override
  void initState() {
    super.initState();
    _radiusKm = widget.initialRadiusKm;
    _restoreInitialVisual();
    _initialiseSpot();
  }

  void _restoreInitialVisual() {
    final visual = widget.initialVisual;
    _bannerBytes = visual.bytes;
    _bannerUrl = visual.url;
    _bannerFileName = visual.fileName;
    _bannerExtension = visual.extension;
    _bannerMimeType = visual.mimeType;
    _bannerFileSizeBytes = visual.fileSizeBytes;
    _bannerWidth = visual.width;
    _bannerHeight = visual.height;
  }

  @override
  void didUpdateWidget(covariant AdvertisingSpotSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position == widget.position) return;
    if (_loadingSavedPosition) {
      _loadingSavedPosition = false;
      return;
    }
    _completed = false;
  }

  Future<void> _initialiseSpot() async {
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
          final advertisingSpot = _map(data['advertisingSpot']);
          final legacyDiffusion = _map(data['diffusion']);

          final latitude = _toDouble(advertisingSpot['latitude']);
          final longitude = _toDouble(advertisingSpot['longitude']);
          final savedRadius = _toDouble(
            advertisingSpot['radiusKm'] ?? legacyDiffusion['radiusKm'],
          );
          if (savedRadius != null &&
              AdvertisingPricingConfig.radiusChoices.contains(savedRadius)) {
            _radiusKm = savedRadius;
          }
          if (latitude != null && longitude != null) {
            final savedPoint = LatLng(latitude, longitude);
            _loadingSavedPosition = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onPositionChanged(savedPoint, centerMap: true);
            });
          }
          final savedBannerUrl = _nullableText(
            advertisingSpot['bannerUrl'] ?? legacyDiffusion['bannerUrl'],
          );
          if (savedBannerUrl != null) {
            _bannerUrl = savedBannerUrl;
            _bannerBytes = null;
            _bannerFileName = _nullableText(
              advertisingSpot['bannerFileName'] ??
                  legacyDiffusion['bannerFileName'],
            );
            _bannerExtension = _nullableText(
              advertisingSpot['bannerExtension'] ??
                  legacyDiffusion['bannerExtension'],
            );
            _bannerMimeType = _nullableText(
              advertisingSpot['bannerMimeType'] ??
                  legacyDiffusion['bannerMimeType'],
            );
            _bannerFileSizeBytes = _toInt(
              advertisingSpot['bannerFileSizeBytes'] ??
                  legacyDiffusion['bannerFileSizeBytes'],
            );
            _bannerWidth = _toInt(
              advertisingSpot['bannerWidth'] ?? legacyDiffusion['bannerWidth'],
            );
            _bannerHeight = _toInt(
              advertisingSpot['bannerHeight'] ??
                  legacyDiffusion['bannerHeight'],
            );
          }
          _completed =
              data['advertisingSpotCompleted'] == true &&
              latitude != null &&
              longitude != null &&
              _bannerUrl != null;
        }
      } catch (error) {
        _error = 'Impossible de charger le SPHOT publicitaire enregistré.';
        debugPrint('Chargement SPHOT publicitaire impossible : $error');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyVisual();
      widget.onRadiusChanged(_radiusKm);
    });
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _toInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String? _nullableText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  void _notifyVisual() {
    widget.onVisualChanged(
      AdvertisingVisualData(
        bytes: _bannerBytes,
        url: _bannerUrl,
        fileName: _bannerFileName,
        extension: _bannerExtension,
        mimeType: _bannerMimeType,
        fileSizeBytes: _bannerFileSizeBytes,
        width: _bannerWidth,
        height: _bannerHeight,
      ),
    );
  }

  void _selectRadius(double radiusKm) {
    setState(() {
      _radiusKm = radiusKm;
      _completed = false;
      _error = null;
    });
    widget.onRadiusChanged(radiusKm);
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
    _notifyVisual();
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
      return 'Ajoutez le visuel qui sera présenté dans les aperçus de diffusion.';
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
    final position = widget.position;
    if (position == null) {
      setState(() {
        _error = 'Cliquez sur la carte pour positionner le SPHOT publicitaire.';
      });
      return;
    }
    if (!_bannerIsValid) {
      setState(() {
        _error = 'Ajoutez un visuel publicitaire conforme avant d’enregistrer.';
      });
      return;
    }

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
              'advertisingSpotCompleted': true,
              'advertisingSpot': <String, Object?>{
                'latitude': position.latitude,
                'longitude': position.longitude,
                'radiusKm': _radiusKm,
                'bannerUrl': bannerUrl,
                'bannerFileName': _bannerFileName,
                'bannerExtension': _bannerExtension,
                'bannerMimeType': _bannerMimeType,
                'bannerFileSizeBytes': _bannerFileSizeBytes,
                'bannerWidth': _bannerWidth,
                'bannerHeight': _bannerHeight,
                'confirmedAt': FieldValue.serverTimestamp(),
              },
              'diffusion': <String, Object?>{'radiusKm': FieldValue.delete()},
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
      _notifyVisual();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'L’enregistrement a échoué. Réessayez.');
      debugPrint('Enregistrement SPHOT publicitaire impossible : $error');
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
      margin: const EdgeInsets.only(bottom: 14),
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
              Icon(Icons.image_outlined, color: WebColors.blue, size: 30),
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

  Widget _buildRadiusCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
                      'ZONE EXCLUSIVE AUTOUR DE VOTRE SPHOT',
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
            children: AdvertisingPricingConfig.radiusChoices.map((radius) {
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
          const SizedBox(height: 14),
          Text(
            'À PARTIR DE ${widget.startingPriceExclTax} € HT / SEMAINE',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WebColors.red,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReachCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'FAITES RAYONNER VOTRE ACTIVITÉ PROFESSIONNELLE EN EXCLUSIVITÉ',
            style: TextStyle(
              color: WebColors.blue,
              fontSize: 16,
              height: 1.25,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 9),
          Text(
            'Choisissez la zone dans laquelle votre établissement bénéficiera d’une présence publicitaire exclusive. Plus le rayon est étendu, plus votre activité gagne en visibilité autour du SPHOT publicitaire.',
            style: TextStyle(
              color: Color(0xFF4B5F97),
              height: 1.4,
              fontWeight: FontWeight.w700,
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
        child: Center(child: CircularProgressIndicator(color: WebColors.red)),
      );
    }

    final position = widget.position;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SpotCard(
          iconWidget: SvgPicture.asset(
            'data/icons/fire_blue_icon.svg',
            width: 30,
            height: 30,
            fit: BoxFit.contain,
          ),
          title: 'POSITION SUR LA CARTE',
          status: position == null ? 'AUCUNE POSITION' : 'POSITION DÉFINIE',
          statusColor: position == null
              ? const Color(0xFF6B7280)
              : WebColors.red,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Déplacez et zoomez la carte, puis cliquez à l’emplacement exact de l’établissement.',
                style: TextStyle(
                  color: Color(0xFF4B5F97),
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _buildBannerCard(),
        _buildReachCard(),
        _buildRadiusCard(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: const TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
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
                  ? 'SPHOT PUBLICITAIRE ENREGISTRÉ'
                  : 'ENREGISTRER LE SPHOT PUBLICITAIRE',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    this.icon,
    this.iconWidget,
    required this.title,
    required this.status,
    required this.child,
    this.statusColor = const Color(0xFF6B7280),
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String title;
  final String status;
  final Widget child;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child:
                    iconWidget ?? Icon(icon, color: WebColors.blue, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
