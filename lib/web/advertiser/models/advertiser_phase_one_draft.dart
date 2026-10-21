import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

/// Brouillon de candidature conserve uniquement dans la memoire de la page.
/// Aucune creation Firestore ni aucun transfert Storage avant l'etape 3.
class AdvertiserPhaseOneDraft {
  AdvertiserPhaseOneDraft._();

  static final Map<String, AdvertiserPhaseOneDraft> _items = {};

  static AdvertiserPhaseOneDraft forRequest(String requestId) =>
      _items.putIfAbsent(requestId, AdvertiserPhaseOneDraft._);

  static void discard(String? requestId) {
    if (requestId != null) _items.remove(requestId);
  }

  final Map<String, Object?> data = <String, Object?>{};
  Uint8List? visualBytes;
  String? visualExtension;
  String? visualMimeType;
  PlatformFile? foreignProofFile;
  bool _requestCreated = false;

  void merge(Map<String, Object?> values) => data.addAll(values);

  Future<void> transmit({
    required String requestId,
    required Map<String, Object?> legalData,
  }) async {
    if (data['profileCompleted'] != true ||
        data['establishmentCompleted'] != true ||
        data['applicationCompleted'] != true) {
      throw StateError('Dossier incomplet : terminez les etapes 1 et 2.');
    }

    final bytes = visualBytes;
    final visual = data['proposedVisual'];
    final visualMap = visual is Map
        ? Map<String, Object?>.from(visual)
        : <String, Object?>{};
    final width = visualMap['width'];
    final height = visualMap['height'];
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > 2 * 1024 * 1024 ||
        width != 1800 ||
        height != 300) {
      throw StateError('Le visuel publicitaire est absent ou non conforme.');
    }
    if (data['registrationMode'] == 'international' &&
        foreignProofFile?.bytes == null) {
      throw StateError('Le justificatif professionnel est manquant.');
    }

    // Si le dossier a ete cree mais que le signal email a echoue,
    // ne pas recreer le dossier ni televerser les fichiers une seconde fois.
    if (_requestCreated) {
      await FirebaseFirestore.instance
          .collection('advertiserRequests')
          .doc(requestId)
          .update({
            'acknowledgementEmail.submissionTriggerAt':
                FieldValue.serverTimestamp(),
          });
      _items.remove(requestId);
      return;
    }

    final uploaded = <Reference>[];
    try {
      final extension = visualExtension ?? 'jpg';
      final visualRef = FirebaseStorage.instance.ref()
          .child('advertiser_requests')
          .child(requestId)
          .child('proposed_visual.$extension');
      await visualRef.putData(
        bytes,
        SettableMetadata(contentType: visualMimeType ?? 'image/jpeg'),
      );
      uploaded.add(visualRef);
      final url = await visualRef.getDownloadURL();

      final payload = <String, Object?>{
        ...data,
        ...legalData,
        'uid': requestId,
        'status': 'pending',
        // Première transmission de la PHASE 1 : événement autonome qui ne
        // disparaît pas lors d'une demande de correction ultérieure.
        'applicationHistory': <Map<String, Object?>>[
          <String, Object?>{
            'event': 'submitted',
            'actor': 'advertiser',
            'occurredAt': Timestamp.now(),
          },
        ],
        'proposedVisual': <String, Object?>{...visualMap, 'url': url},
        'bannerUrl': url,
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // Les suppressions propres aux anciens brouillons ne s'appliquent
      // pas a un nouveau document cree directement a l'etape 3.
      payload.remove('requestedScope');
      payload.remove('centerLat');
      payload.remove('centerLng');

      if (data['registrationMode'] == 'international') {
        final file = foreignProofFile!;
        final proofBytes = file.bytes!;
        final proofExtension = (file.extension ?? 'pdf').toLowerCase();
        final proofRef = FirebaseStorage.instance.ref(
          'advertiser_requests/$requestId/'
          'foreign_registration_proof.$proofExtension',
        );
        await proofRef.putData(
          proofBytes,
          SettableMetadata(
            contentType: proofExtension == 'pdf'
                ? 'application/pdf'
                : 'image/$proofExtension',
          ),
        );
        uploaded.add(proofRef);
        payload['foreignProof'] = <String, Object?>{
          'url': await proofRef.getDownloadURL(),
          'fileName': file.name,
          'extension': proofExtension,
          'fileSizeBytes': file.size,
          'uploadedAt': FieldValue.serverTimestamp(),
        };
      }

      // Premiere et unique creation du dossier a la transmission finale.
      final reference = FirebaseFirestore.instance
          .collection('advertiserRequests')
          .doc(requestId);
      await reference.set(payload);
      _requestCreated = true;
      // La fonction actuelle ecoute les MISES A JOUR. Cette ecriture
      // declenche son mecanisme d'envoi sans nouvelle Cloud Function.
      await reference.update({
        'acknowledgementEmail.submissionTriggerAt':
            FieldValue.serverTimestamp(),
      });
      _items.remove(requestId);
    } catch (_) {
      // Un chargement Storage ne doit pas laisser de fichier orphelin si
      // la creation Firestore echoue. On conserve la saisie pour reessayer.
      if (!_requestCreated) {
        for (final reference in uploaded.reversed) {
          try {
            await reference.delete();
          } catch (_) {
            // Le nettoyage ulterieur reste possible sur cet identifiant.
          }
        }
      }
      rethrow;
    }
  }
}
