import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/web_colors.dart';
import '../models/advertising_visual_data.dart';

class AdvertiserApplicationSection extends StatefulWidget {
  const AdvertiserApplicationSection({
    super.key,
    required this.user,
    required this.requestId,
    required this.position,
    required this.initialVisual,
    required this.requestStatus,
    required this.onPositionChanged,
    required this.onVisualChanged,
    this.onSubmitted,
  });

  final User? user;
  final String? requestId;
  final LatLng? position;
  final AdvertisingVisualData initialVisual;
  final String requestStatus;
  final void Function(LatLng point, {required bool centerMap})
  onPositionChanged;
  final ValueChanged<AdvertisingVisualData> onVisualChanged;
  final VoidCallback? onSubmitted;

  @override
  State<AdvertiserApplicationSection> createState() =>
      _AdvertiserApplicationSectionState();
}

class _AdvertiserApplicationSectionState
    extends State<AdvertiserApplicationSection> {
  final _destinationController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  bool _submitted = false;
  Uint8List? _bannerBytes;
  String? _bannerUrl;
  String? _bannerFileName;
  String? _bannerExtension;
  String? _bannerMimeType;
  int? _bannerFileSizeBytes;
  int? _bannerWidth;
  int? _bannerHeight;
  String? _error;
  String? _success;

  bool get _locked {
    final status = widget.requestStatus.toLowerCase();
    return _submitted || status == 'pending' || status == 'approved';
  }

  bool get _requestTransmitted =>
      _submitted || widget.requestStatus.toLowerCase() == 'pending';

  @override
  void initState() {
    super.initState();
    _restoreVisual(widget.initialVisual);
    _initialise();
  }

  @override
  void didUpdateWidget(covariant AdvertiserApplicationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final status = widget.requestStatus.toLowerCase();
    if (oldWidget.requestStatus != widget.requestStatus &&
        status != 'pending' &&
        status != 'approved') {
      _submitted = false;
      _success = null;
    }
  }

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  void _restoreVisual(AdvertisingVisualData visual) {
    _bannerBytes = visual.bytes;
    _bannerUrl = visual.url;
    _bannerFileName = visual.fileName;
    _bannerExtension = visual.extension;
    _bannerMimeType = visual.mimeType;
    _bannerFileSizeBytes = visual.fileSizeBytes;
    _bannerWidth = visual.width;
    _bannerHeight = visual.height;
  }

  Future<void> _initialise() async {
    final requestId = widget.requestId;
    if (requestId != null && requestId.isNotEmpty) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(requestId)
            .get();
        final data = snapshot.data();
        if (data != null) {
          final application = _map(data['application']);
          final location = _map(data['applicantLocation']);
          final visual = _map(
            data['proposedVisual'] ?? application['proposedVisual'],
          );
          _destinationController.text = _text(
            application['destinationUrl'] ?? data['destinationUrl'],
          );

          final latitude = _double(location['latitude']);
          final longitude = _double(location['longitude']);
          if (latitude != null && longitude != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onPositionChanged(
                LatLng(latitude, longitude),
                centerMap: true,
              );
            });
          }

          final savedUrl = _text(visual['url'] ?? data['bannerUrl']);
          if (savedUrl.isNotEmpty) {
            _bannerBytes = null;
            _bannerUrl = savedUrl;
            _bannerFileName = _nullableText(visual['fileName']);
            _bannerExtension = _nullableText(visual['extension']);
            _bannerMimeType = _nullableText(visual['mimeType']);
            _bannerFileSizeBytes = _int(visual['fileSizeBytes']);
            _bannerWidth = _int(visual['width']);
            _bannerHeight = _int(visual['height']);
          }
        }
      } catch (error) {
        _error = 'Impossible de charger la demande enregistrée.';
        debugPrint('Chargement candidature annonceur impossible : $error');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    _notifyVisual();
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  String _text(Object? value) => value?.toString().trim() ?? '';

  String? _nullableText(Object? value) {
    final valueText = _text(value);
    return valueText.isEmpty ? null : valueText;
  }

  double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_text(value));
  }

  int? _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(_text(value));
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

  Future<void> _pickBanner() async {
    if (_locked) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final fileName = picked.name;
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    const allowedExtensions = {'png', 'jpg', 'jpeg', 'webp'};
    if (!allowedExtensions.contains(extension)) {
      setState(() => _error = 'Format refusé. Utilisez PNG, JPG ou WEBP.');
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
      _bannerUrl = null;
      _bannerFileName = fileName;
      _bannerExtension = extension;
      _bannerMimeType = mimeType;
      _bannerFileSizeBytes = bytes.length;
      _bannerWidth = image.width;
      _bannerHeight = image.height;
      _error = null;
      _success = null;
    });
    _notifyVisual();
  }

  bool get _bannerIsValid {
    if (_bannerUrl != null && _bannerBytes == null) return true;
    final width = _bannerWidth;
    final height = _bannerHeight;
    final size = _bannerFileSizeBytes;
    if (width == null || height == null || size == null) return false;
    if (size > 2 * 1024 * 1024) return false;
    if (width < 900 || height < 450 || width > 2400 || height > 1200) {
      return false;
    }
    final ratio = width / height;
    return ratio >= 1.85 && ratio <= 2.15;
  }

  String get _visualMessage {
    if (_bannerBytes == null && _bannerUrl == null) {
      return 'Ajoutez le visuel que le Super Admin devra contrôler.';
    }
    if (_bannerIsValid) {
      return _bannerWidth == null
          ? 'Visuel publicitaire enregistré.'
          : 'Visuel compatible : $_bannerWidth × $_bannerHeight px.';
    }
    return 'Visuel non conforme : format proche de 1200 × 600 px, 2 Mo maximum.';
  }

  Future<String?> _uploadBanner(String requestId) async {
    final bytes = _bannerBytes;
    if (bytes == null) return _bannerUrl;
    final extension = _bannerExtension ?? 'jpg';
    final reference = FirebaseStorage.instance
        .ref()
        .child('advertiser_requests')
        .child(requestId)
        .child('proposed_visual.$extension');
    await reference.putData(
      bytes,
      SettableMetadata(contentType: _bannerMimeType ?? 'image/jpeg'),
    );
    return reference.getDownloadURL();
  }

  bool _destinationIsValid(String value) {
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    return uri != null && uri.host.contains('.');
  }

  Future<void> _submit() async {
    if (_locked || _submitting) return;
    final requestId = widget.requestId;
    final position = widget.position;
    final destination = _destinationController.text.trim();

    if (requestId == null || requestId.isEmpty) {
      setState(() => _error = 'Identifiez-vous avant d’envoyer la demande.');
      return;
    }
    if (position == null) {
      setState(() => _error = 'Choisissez votre position sur la carte.');
      return;
    }
    if (!_bannerIsValid) {
      setState(() => _error = 'Ajoutez un visuel publicitaire conforme.');
      return;
    }
    if (destination.isEmpty || !_destinationIsValid(destination)) {
      setState(() => _error = 'Renseignez une adresse de destination valide.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _success = null;
    });

    try {
      final reference = FirebaseFirestore.instance
          .collection('advertiserRequests')
          .doc(requestId);
      final snapshot = await reference.get();
      final data = snapshot.data() ?? <String, dynamic>{};
      if (data['profileCompleted'] != true ||
          data['establishmentCompleted'] != true) {
        throw const _ApplicationException(
          'Enregistrez d’abord toutes les informations de l’étape 1.',
        );
      }

      final bannerUrl = await _uploadBanner(requestId);
      final normalizedDestination = destination.contains('://')
          ? destination
          : 'https://$destination';
      final recipient = _text(
        data['contactEmail'] ?? widget.user?.email ?? data['email'],
      );

      await reference.set({
        'uid': requestId,
        'status': 'pending',
        'requestedScope': FieldValue.delete(),
        'destinationUrl': normalizedDestination,
        'centerLat': FieldValue.delete(),
        'centerLng': FieldValue.delete(),
        'applicantLocation': <String, Object?>{
          'latitude': position.latitude,
          'longitude': position.longitude,
          'selectedAt': FieldValue.serverTimestamp(),
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
        'bannerUrl': bannerUrl,
        'application': <String, Object?>{
          'destinationUrl': normalizedDestination,
          'submittedAt': FieldValue.serverTimestamp(),
        },
        'applicationCompleted': true,
        'acknowledgementEmail': <String, Object?>{
          'status': 'pending',
          'recipient': recipient,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'review': <String, Object?>{
          'status': 'pending',
          'reason': '',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _bannerUrl = bannerUrl;
        _bannerBytes = null;
        _submitted = true;
        _success = 'Votre demande a été transmise au Super Admin.';
      });
      widget.onSubmitted?.call();
      _notifyVisual();
    } on _ApplicationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'L’envoi a échoué. Réessayez.');
      }
      debugPrint('Envoi candidature annonceur impossible : $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _card({
    IconData? icon,
    Widget? iconWidget,
    required String title,
    required Widget child,
    String? subtitle,
    Color subtitleColor = const Color(0xFF6B7280),
  }) {
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
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: subtitleColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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

  Widget _statusCard() {
    final status = _requestTransmitted
        ? 'pending'
        : widget.requestStatus.toLowerCase();
    final (label, color, message) = switch (status) {
      'pending' => (
        'EN COURS DE TRAITEMENT',
        const Color(0xFFF59E0B),
        'Votre dossier est verrouillé pendant son contrôle par le Super Admin.',
      ),
      'changes_requested' => (
        'MODIFICATIONS DEMANDÉES',
        WebColors.red,
        'Corrigez les éléments signalés puis transmettez à nouveau votre demande.',
      ),
      'rejected' => (
        'DEMANDE REFUSÉE',
        WebColors.red,
        'Consultez le motif communiqué par le Super Admin.',
      ),
      'approved' => (
        'DEMANDE APPROUVÉE',
        const Color(0xFF15803D),
        'Vos identifiants de connexion ont été envoyés par email. Utilisez-les pour ouvrir votre espace annonceur complet.',
      ),
      _ => (
        'DEMANDE À COMPLÉTER',
        const Color(0xFF6B7280),
        'Complétez les deux étapes avant de transmettre votre demande.',
      ),
    };
    return _card(
      icon: Icons.fact_check_outlined,
      title: label,
      subtitle: message,
      child: Text(
        status == 'changes_requested' || status == 'rejected'
            ? 'Les informations approuvées précédemment restent inchangées tant qu’une nouvelle version n’a pas été validée.'
            : 'Vous recevrez un email de confirmation dès l’enregistrement de la demande, puis un second email après la décision.',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _positionCard() {
    return _card(
      iconWidget: SvgPicture.asset(
        'data/icons/fire_red_icon.svg',
        width: 30,
        height: 30,
        fit: BoxFit.contain,
      ),
      title: 'POSITION DE VOTRE ENTREPRISE',
      subtitle: widget.position == null
          ? 'AUCUNE POSITION'
          : 'POSITION DÉFINIE',
      subtitleColor: widget.position == null
          ? const Color(0xFF6B7280)
          : WebColors.red,
      child: Text(
        _locked ? 'La position de votre entreprise est en cours de contrôle.' : 'Déplacez et zoomez la carte, puis cliquez à l’emplacement exact de votre entreprise ; votre SPHOT sera ainsi défini.',
        style: const TextStyle(
          color: Color(0xFF4B5F97),
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _visualCard() {
    final preview = _bannerBytes != null
        ? Image.memory(_bannerBytes!, fit: BoxFit.contain)
        : _bannerUrl != null
        ? Image.network(_bannerUrl!, fit: BoxFit.contain)
        : null;
    return _card(
      icon: Icons.image_outlined,
      title: 'VISUEL PUBLICITAIRE',
      subtitle: 'FORMAT RECOMMANDÉ\n1200 × 600 px\nMaxi 2 Mo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preview != null) ...[
            AspectRatio(
              aspectRatio: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: const Color(0xFFF2F5FA),
                  child: preview,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _locked || _submitting ? null : _pickBanner,
            style: FilledButton.styleFrom(
              backgroundColor: _bannerIsValid ? WebColors.red : WebColors.blue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _bannerIsValid
                  ? WebColors.red
                  : const Color(0xFF94A3B8),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(
              _bannerIsValid ? 'VISUEL AJOUTÉ' : 'AJOUTER LE VISUEL',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _visualMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _bannerIsValid ? WebColors.blue : WebColors.red,
              fontSize: 12,
              fontWeight: FontWeight.w800,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_submitted ||
            <String>{
              'pending',
              'changes_requested',
              'rejected',
              'approved',
            }.contains(widget.requestStatus.toLowerCase()))
          _statusCard(),
        _positionCard(),
        _visualCard(),
        _card(
          icon: Icons.link_rounded,
          title: 'DESTINATION DU SPHOT PUBLICITAIRE',
          subtitle: 'PAGE OU SITE OUVERT APRÈS LE CLIC',
          child: TextField(
            controller: _destinationController,
            readOnly: _locked,
            keyboardType: TextInputType.url,
            style: const TextStyle(
              color: WebColors.blue,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: 'https://www.votre-site.fr',
              hintStyle: const TextStyle(color: Color(0xFF4B5F97)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: WebColors.blue),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: WebColors.blue, width: 2),
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        if (_success != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _success!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF15803D),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _locked || _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _requestTransmitted
                  ? WebColors.red
                  : WebColors.blue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _requestTransmitted
                  ? WebColors.red
                  : const Color(0xFF94A3B8),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    _requestTransmitted
                        ? Icons.check_circle_outline_rounded
                        : Icons.send_rounded,
                  ),
            label: Text(
              _submitting
                  ? 'ENVOI EN COURS…'
                  : _requestTransmitted
                  ? 'DEMANDE TRANSMISE'
                  : 'TRANSMETTRE LA DEMANDE',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _ApplicationException implements Exception {
  const _ApplicationException(this.message);

  final String message;
}
