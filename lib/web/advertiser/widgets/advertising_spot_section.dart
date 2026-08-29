import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/web_colors.dart';

class AdvertisingSpotSection extends StatefulWidget {
  const AdvertisingSpotSection({
    super.key,
    required this.user,
    required this.position,
    required this.onPositionChanged,
  });

  final User? user;
  final LatLng? position;
  final void Function(LatLng point, {required bool centerMap})
      onPositionChanged;

  @override
  State<AdvertisingSpotSection> createState() =>
      _AdvertisingSpotSectionState();
}

class _AdvertisingSpotSectionState extends State<AdvertisingSpotSection> {
  bool _loading = true;
  bool _saving = false;
  bool _completed = false;
  bool _requestExists = false;
  bool _loadingSavedPosition = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialiseSpot();
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

          final latitude = _toDouble(advertisingSpot['latitude']);
          final longitude = _toDouble(advertisingSpot['longitude']);
          if (latitude != null && longitude != null) {
            final savedPoint = LatLng(latitude, longitude);
            _loadingSavedPosition = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onPositionChanged(savedPoint, centerMap: true);
            });
          }
          _completed = data['advertisingSpotCompleted'] == true &&
              latitude != null &&
              longitude != null;
        }
      } catch (error) {
        _error = 'Impossible de charger le SPHOT publicitaire enregistré.';
        debugPrint('Chargement SPHOT publicitaire impossible : $error');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> _save() async {
    final position = widget.position;
    if (position == null) {
      setState(() {
        _error = 'Cliquez sur la carte pour positionner le SPHOT publicitaire.';
      });
      return;
    }

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
          'advertisingSpotCompleted': true,
          'advertisingSpot': <String, Object?>{
            'latitude': position.latitude,
            'longitude': position.longitude,
            'confirmedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _requestExists = true;
      }

      if (!mounted) return;
      setState(() => _completed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SPHOT publicitaire enregistré.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'L’enregistrement a échoué. Réessayez.');
      debugPrint('Enregistrement SPHOT publicitaire impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                child: iconWidget ??
                    Icon(icon, color: WebColors.blue, size: 30),
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
