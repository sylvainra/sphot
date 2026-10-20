import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/advertising_pricing_config.dart';
import '../services/advertiser_territory_service.dart';
import '../../shared/web_colors.dart';
import '../models/advertising_visual_data.dart';
import 'advertiser_cgv_policy.dart';

class AdvertisingSpotSection extends StatefulWidget {
  const AdvertisingSpotSection({
    super.key,
    required this.user,
    this.requestId,
    required this.position,
    required this.initialVisual,
    required this.initialRadiusKm,
    required this.startingPriceExclTax,
    required this.onPositionChanged,
    required this.onVisualChanged,
    required this.onRadiusChanged,
    required this.onScopeChanged,
    required this.onTerritoryChanged,
    this.initialTerritory,
    this.approvedAssetsLocked = false,
    this.assetChangeMode = false,
    this.assetChangeRequestStatus = '',
    this.radiusChangeRequest = const {},
    this.requestedScope = 'local',
  });

  final User? user;
  final String? requestId;
  final LatLng? position;
  final AdvertisingVisualData initialVisual;
  final double initialRadiusKm;
  final int startingPriceExclTax;
  final void Function(LatLng point, {required bool centerMap})
  onPositionChanged;
  final ValueChanged<AdvertisingVisualData> onVisualChanged;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<String> onScopeChanged;
  final ValueChanged<AdvertiserTerritory> onTerritoryChanged;
  final AdvertiserTerritory? initialTerritory;
  final bool approvedAssetsLocked;
  final bool assetChangeMode;
  final String assetChangeRequestStatus;
  final Map<String, dynamic> radiusChangeRequest;
  final String requestedScope;

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
  String _scope = 'local';
  AdvertiserTerritory? _territory;
  AdvertiserTerritory? _approvedTerritory;
  Map<String, dynamic> _activeRadiusRequest = {};
  LatLng? _approvedPosition;
  String? _approvedVisualUrl;
  bool _radiusTermsAccepted = false;

  bool get _radiusRequestPending =>
      <String>{'waiting_period_end', 'approved_pending_payment'}
          .contains(_activeRadiusRequest['status']);

  bool get _radiusChanged {
    if (!widget.assetChangeMode) return false;
    final approved = _approvedTerritory;
    final proposed = _territory;
    if (approved == null || proposed == null) return false;
    return approved.level != proposed.level || approved.code != proposed.code;
  }
  AdvertiserTerritoryOptions? _territoryOptions;
  final AdvertiserTerritoryService _territoryService =
      AdvertiserTerritoryService();
  bool _territoryLoading = false;
  String? _territoryError;
  int _territoryRequestNumber = 0;
  Uint8List? _bannerBytes;
  String? _bannerUrl;
  String? _bannerFileName;
  String? _bannerExtension;
  String? _bannerMimeType;
  int? _bannerFileSizeBytes;
  int? _bannerWidth;
  int? _bannerHeight;
  String? _error;

  String? get _requestId {
    final value = widget.requestId?.trim() ?? '';
    if (value.isNotEmpty) return value;
    return widget.user?.uid;
  }

  @override
  void initState() {
    super.initState();
    _radiusKm = widget.initialRadiusKm;
    _scope = widget.requestedScope;
    _territory = widget.initialTerritory;
    _restoreInitialVisual();
    _initialiseSpot();
  }

  @override
  void dispose() {
    _territoryRequestNumber++;
    _territoryService.dispose();
    super.dispose();
  }

  Future<void> _loadTerritories(LatLng position) async {
    final request = ++_territoryRequestNumber;
    if (mounted) {
      setState(() {
        _territoryLoading = true;
        _territoryError = null;
      });
    }
    try {
      final options = await _territoryService.resolve(position);
      if (!mounted || request != _territoryRequestNumber) return;
      final previous = _territory;
      final option = previous != null ? options[previous.level] : null;
      final selected = option != null && option.code == previous!.code
          ? option
          : null;
      setState(() {
        _territoryOptions = options;
        _territory = selected;
        _territoryLoading = false;
      });
      if (selected != null) widget.onTerritoryChanged(selected);
    } catch (_) {
      if (!mounted || request != _territoryRequestNumber) return;
      setState(() {
        _territoryOptions = null;
        _territoryLoading = false;
        _territoryError =
            'Impossible de préparer les zones. Réessayez.';
      });
    }
  }

  void _selectTerritory(AdvertiserTerritory selected) {
    setState(() {
      _territory = selected;
      _radiusTermsAccepted = false;
      _completed = false;
      _error = null;
    });
    widget.onTerritoryChanged(selected);
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
    final newRadiusStatus =
        widget.radiusChangeRequest['status']?.toString() ?? '';
    final oldRadiusStatus =
        oldWidget.radiusChangeRequest['status']?.toString() ?? '';
    if (newRadiusStatus != oldRadiusStatus) {
      _activeRadiusRequest = _map(widget.radiusChangeRequest);
      if (newRadiusStatus == 'waiting_period_end' ||
          newRadiusStatus == 'rejected' ||
          newRadiusStatus == 'approved_pending_payment') {
        // Ne conserver dans la sélection aucun rayon refusé ou non payé.
        _territory = _approvedTerritory;
        _radiusTermsAccepted = false;
        final approved = _approvedTerritory;
        if (approved != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onTerritoryChanged(approved);
          });
        }
      }
    }
    if (oldWidget.requestedScope != widget.requestedScope &&
        _scope != widget.requestedScope) {
      _scope = widget.requestedScope;
    }
    if (oldWidget.position == widget.position) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final position = widget.position;
      if (position != null) {
        _loadTerritories(position);
      } else {
        setState(() {
          _territory = null;
          _territoryOptions = null;
        });
      }
    });
    if (_loadingSavedPosition) {
      _loadingSavedPosition = false;
      return;
    }
    _completed = false;
  }

  Future<void> _initialiseSpot() async {
    final requestId = _requestId;
    if (requestId != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(requestId)
            .get();
        final data = snapshot.data();
        _requestExists = snapshot.exists;

        if (data != null) {
          final approvedApplication = _map(data['approvedApplication']);
          _approvedTerritory = AdvertiserTerritory.fromFirestore(
            data['advertisingTerritory'],
          );
          _activeRadiusRequest = _map(data['radiusChangeRequest']);
          final approvedLocation = _map(approvedApplication['location']);
          final approvedVisual = _map(approvedApplication['visual']);
          final advertisingSpot = _map(data['advertisingSpot']);
          _territory = AdvertiserTerritory.fromFirestore(
                data['advertisingTerritory'],
              ) ??
              _territory;
          final applicantLocation = _map(data['applicantLocation']);
          final proposedVisual = _map(data['proposedVisual']);
          final legacyDiffusion = _map(data['diffusion']);

          final latitude = _toDouble(
            approvedLocation['latitude'] ??
                advertisingSpot['latitude'] ??
                applicantLocation['latitude'],
          );
          final longitude = _toDouble(
            approvedLocation['longitude'] ??
                advertisingSpot['longitude'] ??
                applicantLocation['longitude'],
          );
          final savedRadius = _toDouble(
            advertisingSpot['radiusKm'] ?? legacyDiffusion['radiusKm'],
          );
          final savedScope =
              (advertisingSpot['scope'] ??
                      data['requestedScope'] ??
                      approvedApplication['scope'])
                  ?.toString();
          if (<String>{
            'local',
            'national',
            'local_and_national',
          }.contains(savedScope)) {
            _scope = savedScope!;
          }
          if (savedRadius != null &&
              AdvertisingPricingConfig.radiusChoices.contains(savedRadius)) {
            _radiusKm = savedRadius;
          }
          if (latitude != null && longitude != null) {
            _approvedPosition = LatLng(latitude, longitude);
            final savedPoint = LatLng(latitude, longitude);
            _loadingSavedPosition = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onPositionChanged(savedPoint, centerMap: true);
            });
          }
          final savedBannerUrl = _nullableText(
            approvedVisual['url'] ??
                advertisingSpot['bannerUrl'] ??
                proposedVisual['url'] ??
                legacyDiffusion['bannerUrl'],
          );
          _approvedVisualUrl = savedBannerUrl;
          if (savedBannerUrl != null) {
            _bannerUrl = savedBannerUrl;
            _bannerBytes = null;
            _bannerFileName = _nullableText(
              approvedVisual['fileName'] ??
                  advertisingSpot['bannerFileName'] ??
                  proposedVisual['fileName'] ??
                  legacyDiffusion['bannerFileName'],
            );
            _bannerExtension = _nullableText(
              approvedVisual['extension'] ??
                  advertisingSpot['bannerExtension'] ??
                  proposedVisual['extension'] ??
                  legacyDiffusion['bannerExtension'],
            );
            _bannerMimeType = _nullableText(
              approvedVisual['mimeType'] ??
                  advertisingSpot['bannerMimeType'] ??
                  proposedVisual['mimeType'] ??
                  legacyDiffusion['bannerMimeType'],
            );
            _bannerFileSizeBytes = _toInt(
              approvedVisual['fileSizeBytes'] ??
                  advertisingSpot['bannerFileSizeBytes'] ??
                  proposedVisual['fileSizeBytes'] ??
                  legacyDiffusion['bannerFileSizeBytes'],
            );
            _bannerWidth = _toInt(
              approvedVisual['width'] ??
                  advertisingSpot['bannerWidth'] ??
                  proposedVisual['width'] ??
                  legacyDiffusion['bannerWidth'],
            );
            _bannerHeight = _toInt(
              approvedVisual['height'] ??
                  advertisingSpot['bannerHeight'] ??
                  proposedVisual['height'] ??
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
    if (widget.position != null) _loadTerritories(widget.position!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyVisual();
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

  void _selectScope(String scope) {
    if (_scope == scope) return;
    setState(() {
      _scope = scope;
      _completed = false;
      _error = null;
    });
    widget.onScopeChanged(scope);
  }

  Future<void> _pickBanner() async {
    if (widget.approvedAssetsLocked) return;
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
    return width == 1800 && height == 300;
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
      return 'Visuel non conforme : dimensions requises : 1800 × 300 px.';
    }
    if (_bannerWidth == 1800 && _bannerHeight == 300) {
      return 'Visuel conforme SPHOT : 1800 × 300 px.';
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
    if (widget.approvedAssetsLocked) return;
    final position = widget.position;
    final territory = _territory;
    if (territory == null ||
        _territoryOptions?[territory.level]?.code != territory.code) {
      setState(() {
        _error = 'Sélectionnez un des cinq rayons ou le pays entier.';
      });
      return;
    }
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

    if (_radiusChanged && !_radiusTermsAccepted) {
      setState(() {
        _error = 'Confirmez les conditions de report et de tarification '
            'du changement de rayon avant de soumettre.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final requestId = _requestId;
      var bannerUrl = _bannerUrl;
      if (requestId != null) {
        bannerUrl = await _uploadBanner(requestId);
        final creationData = _requestExists
            ? <String, Object?>{}
            : <String, Object?>{
                'status': 'draft',
                'createdAt': FieldValue.serverTimestamp(),
              };
        final requestReference = FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(requestId);
        if (widget.assetChangeMode) {
          // La période payée conserve la zone actuelle. Séparer la
          // proposition de rayon des visuels/positions examinables de suite.
          final approved = _approvedPosition;
          final locationChanged = approved != null &&
              ((approved.latitude - position.latitude).abs() > 0.000001 ||
               (approved.longitude - position.longitude).abs() > 0.000001);
          final visualChanged = _bannerBytes != null ||
              (_approvedVisualUrl != null &&
               _approvedVisualUrl != bannerUrl);
          final assetsChanged = visualChanged || locationChanged;
          final radiusChanged = _radiusChanged;

          if (!assetsChanged && !radiusChanged) {
            throw StateError('Aucun changement à soumettre.');
          }
          final changes = <String, Object?>{
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (assetsChanged) {
            changes['assetChangeRequest'] = <String, Object?>{
              'status': 'submitted',
              'proposedLocation': <String, Object?>{
                'latitude': position.latitude,
                'longitude': position.longitude,
              },
              'proposedVisual': <String, Object?>{
                'url': bannerUrl,
                'fileName': _bannerFileName,
                'extension': _bannerExtension,
                'mimeType': _bannerMimeType,
                'fileSizeBytes': _bannerFileSizeBytes,
                'width': _bannerWidth,
                'height': _bannerHeight,
              },
              'submittedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            };
          }
          if (radiusChanged) {
            // Vérifier le dossier à nouveau juste avant la soumission :
            // le rayon contractuel ou la demande peuvent avoir changé
            // depuis le chargement de ce formulaire.
            final latest = (await requestReference.get()).data() ?? {};
            final liveTerritory = AdvertiserTerritory.fromFirestore(
              latest['advertisingTerritory'],
            );
            final liveRequest = _map(latest['radiusChangeRequest']);
            if (liveTerritory == null ||
                liveTerritory.level != _approvedTerritory?.level ||
                liveTerritory.code != _approvedTerritory?.code) {
              throw StateError(
                'Le rayon contractuel a changé. Actualisez la page.',
              );
            }
            if (<String>{'waiting_period_end', 'approved_pending_payment'}
                .contains(liveRequest['status'])) {
              throw StateError(
                'Une demande de rayon est déjà en attente de traitement.',
              );
            }
            final cgvSnapshot = await FirebaseFirestore.instance
                .collection('legalDocuments')
                .doc(AdvertiserCgvPolicy.documentId).get();
            final cgvVersion = (cgvSnapshot.data()?['version'] ??
                AdvertiserCgvPolicy.defaultVersion).toString();
            changes['radiusChangeRequest'] = <String, Object?>{
              'status': 'waiting_period_end',
              'previousTerritory': _approvedTerritory!.toFirestore(),
              'proposedTerritory': territory.toFirestore(),
              'priceAcknowledged': true,
              'noticeVersion': '2026-10-20',
              'cgvVersionAccepted': cgvVersion,
              'acceptedAt': FieldValue.serverTimestamp(),
              'submittedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            };
          }
          await requestReference.set(changes, SetOptions(merge: true));
          if (radiusChanged) {
            _activeRadiusRequest = {
              'status': 'waiting_period_end',
              'previousTerritory': _approvedTerritory?.toFirestore(),
              'proposedTerritory': territory.toFirestore(),
            };
            // Une sélection proposée ne devient pas le rayon diffusé.
            _territory = _approvedTerritory;
            if (_approvedTerritory != null) {
              widget.onTerritoryChanged(_approvedTerritory!);
            }
          }
        } else {
          await requestReference.set({
            ...creationData,
            'uid': requestId,
            'advertisingTerritory': territory.toFirestore(),
            'advertisingSpotCompleted': true,
            'advertisingSpot': <String, Object?>{
              'latitude': position.latitude,
              'longitude': position.longitude,
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
        }
        _requestExists = true;
      }

      if (!mounted) return;
      setState(() {
        _bannerUrl = bannerUrl;
        if (requestId != null) _bannerBytes = null;
        _completed = true;
      });
      _notifyVisual();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is StateError
            ? error.message
            : 'L’enregistrement a échoué. Réessayez.';
      });
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
                      'BANNIÈRE HORIZONTALE : 1800 × 300 PX',
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
          if (hasBanner) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 6,
                child: _bannerBytes != null
                    ? Image.memory(_bannerBytes!, fit: BoxFit.contain)
                    : Image.network(
                        _bannerUrl!,
                        fit: BoxFit.contain,
                        // Sur Flutter Web, autoriser l'affichage HTML des
                        // images Firebase Storage lorsque CanvasKit est bloque
                        // par les restrictions CORS.
                        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                        errorBuilder: (context, error, stackTrace) {
                          // Ne pas journaliser l'URL : elle peut contenir un
                          // jeton d'acces Firebase Storage.
                          debugPrint(
                            'Apercu du visuel publicitaire impossible : '
                            '${error.runtimeType}',
                          );
                          return const Center(
                            child: Text(
                              'Le visuel ne peut pas être affiché.',
                              style: TextStyle(color: WebColors.red),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          OutlinedButton.icon(
            onPressed: _saving || widget.approvedAssetsLocked
                ? null
                : _pickBanner,
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
              widget.approvedAssetsLocked
                  ? 'VISUEL VALIDÉ — LECTURE SEULE'
                  : hasBanner
                  ? 'REMPLACER LE VISUEL'
                  : 'AJOUTER LE VISUEL',
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

  Widget _buildTerritoryCard() {
    final options = _territoryOptions;
    final current = _territory;
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
            children: [
              Icon(Icons.public_outlined, color: WebColors.blue, size: 30),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'ZONE DE DIFFUSION',
                  style: TextStyle(
                    color: WebColors.blue,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Cinq rayons rouges ou le pays entier en rouge, '
            'partout dans le monde. Aucune exclusivité.',
            style: TextStyle(
              color: Color(0xFF4B5F97),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (_territoryLoading)
            const Center(child: CircularProgressIndicator())
          else if (options == null)
            Column(
              children: [
                Text(
                  _territoryError ??
                      'Positionnez votre SPHOT pour choisir sa zone.',
                  style: const TextStyle(color: WebColors.red),
                ),
                if (widget.position != null)
                  TextButton(
                    onPressed: () => _loadTerritories(widget.position!),
                    child: const Text('RÉESSAYER'),
                  ),
              ],
            )
          else ...[
            if (options[AdvertiserTerritoryLevel.wholeCountry] == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'PAYS ENTIER indisponible pour cet emplacement : '
                  'vérifiez la connexion et la position.',
                  style: TextStyle(color: WebColors.red, fontSize: 12),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final level in AdvertiserTerritoryLevel.values)
                  if (options[level] != null)
                    OutlinedButton(
                      onPressed:
                          widget.approvedAssetsLocked || _radiusRequestPending
                              ? null
                              : () => _selectTerritory(options[level]!),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: current?.level == level
                            ? Colors.white
                            : WebColors.blue,
                        backgroundColor: current?.level == level
                            ? WebColors.red
                            : Colors.white,
                        side: BorderSide(
                          color: current?.level == level
                              ? WebColors.red
                              : WebColors.blue,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      child: Text(
                        level.label,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: 12),
              Text(
                current.isWholeCountry
                    ? 'PAYS ENTIER : ${current.name}'
                    : current.level.label,
                style: const TextStyle(
                  color: WebColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                current.isWholeCountry
                    ? 'Le contour rouge représente ${current.name} '
                        '(frontières cartographiques indicatives).'
                    : 'La zone rouge représente un rayon de '
                        '${current.level.label} autour du SPHOT.',
                style: const TextStyle(
                  color: Color(0xFF4B5F97),
                  fontSize: 12,
                ),
              ),
            ],
          ],
          if (_radiusChanged && widget.assetChangeMode &&
              !_radiusRequestPending) ...[
            const SizedBox(height: 14),
            const Text(
              'IMPORTANT — Un changement de rayon, en hausse ou en baisse, '
              'reste sans effet jusqu’à la fin de la période publicitaire '
              'déjà engagée. Après l’échéance, il nécessite un nouvel accord '
              'commercial et le paiement correspondant. La zone actuelle '
              'et son tarif restent inchangés.',
              style: TextStyle(
                color: WebColors.red,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _radiusTermsAccepted,
              onChanged: (value) => setState(
                () => _radiusTermsAccepted = value ?? false,
              ),
              title: const Text(
                'Je reconnais le report du nouveau rayon après la période '
                'en cours et son nouveau tarif pour la période suivante.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
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
        _buildBannerCard(),
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
              Text(
                widget.approvedAssetsLocked
                    ? 'Position validée par SPHOT. Demandez une modification pour proposer un nouvel emplacement.'
                    : 'Déplacez et zoomez la carte, puis cliquez à l’emplacement exact de votre SPHOT publicitaire.',
                style: const TextStyle(
                  color: Color(0xFF4B5F97),
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _buildTerritoryCard(),
        if (_activeRadiusRequest['status'] == 'waiting_period_end')
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'RAYON ACTUEL : ' +
              (_approvedTerritory?.level.label ?? 'Non renseigné') +
              ' — RAYON DEMANDÉ : ' +
              (AdvertiserTerritory.fromFirestore(
                _activeRadiusRequest['proposedTerritory'],
              )?.level.label ?? 'Non renseigné') +
              ' — EN ATTENTE DE FIN DE PÉRIODE. '
              'La zone actuellement payée reste inchangée.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WebColors.red, fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (_activeRadiusRequest['status'] == 'rejected')
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'Changement de rayon refusé. '
              'Le rayon contractuel demeure inchangé.',
              style: TextStyle(
                color: WebColors.red, fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (widget.assetChangeRequestStatus == 'submitted')
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'Votre proposition de modification du visuel et/ou de la '
              'position est en attente d’approbation. '
              'Toute demande de rayon est traitée séparément '
              'à l’échéance contractuelle. Le contenu déjà approuvé '
              'reste en vigueur.',
              textAlign: TextAlign.center,
              style: TextStyle(color: WebColors.red, fontWeight: FontWeight.w800),
            ),
          ),
        if (widget.assetChangeMode)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'Proposez une modification du visuel et/ou de la position '
              'et/ou du rayon d’action. Le rayon est traité séparément '
              'et n’est pas applicable avant l’échéance contractuelle '
              'et les nouvelles conditions commerciales.',
              textAlign: TextAlign.center,
              style: TextStyle(color: WebColors.blue, fontWeight: FontWeight.w700),
            ),
          ),

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
            onPressed: _saving || widget.approvedAssetsLocked ? null : _save,
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
                  : widget.assetChangeMode
                  ? (_completed
                      ? 'PROPOSITION TRANSMISE POUR APPROBATION'
                      : 'SOUMETTRE LA MODIFICATION À APPROBATION')
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
