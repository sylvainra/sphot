"use strict";

// Correction PHASE 1 uniquement : la décision et sa chronologie sont
// exclusivement réécrites par le serveur après vérification Firebase Auth.
const SCOPE_NAMES = new Set([
  "identity", "establishment", "location", "visual", "destination", "legal",
]);

/**
 * Émet une réponse d'erreur sans divulguer les détails serveur.
 * @param {Object} response Réponse HTTP.
 * @param {number} code Statut HTTP.
 * @param {string} message Message destiné au demandeur.
 * @return {void}
 */
function responseError(response, code, message) {
  response.status(code).json({success: false, error: message});
}

/**
 * Déclare le point d'entrée serveur de retransmission des corrections.
 * @param {Object} dependencies Dépendances Firebase.
 * @return {Function} Gestionnaire HTTP de retransmission.
 */
function registerAdvertiserCorrectionResubmit({admin, onRequest}) {
  return onRequest(
      {region: "us-central1", cors: true, cpu: 1, memory: "256MiB"},
      async (request, response) => {
        if (request.method !== "POST") {
          responseError(response, 405, "Méthode non autorisée.");
          return;
        }
        const body = request.body || {};
        const requestId = typeof body.requestId === "string" ?
          body.requestId.trim() : "";
        if (!/^[a-zA-Z0-9_-]{8,128}$/.test(requestId) ||
            Object.keys(body).some((key) => ![
              "requestId", "legalAcceptance", "legalVersion",
              "advertiserCgvVersion",
            ].includes(key))) {
          responseError(response, 400, "Demande de transmission invalide.");
          return;
        }
        if (body.legalAcceptance !== true &&
            body.legalAcceptance !== false) {
          responseError(response, 400, "Déclaration juridique invalide.");
          return;
        }
        const header = request.headers.authorization || "";
        if (!header.startsWith("Bearer ")) {
          responseError(response, 401, "Session annonceur absente.");
          return;
        }
        let identity;
        try {
          identity = await admin.auth().verifyIdToken(header.slice(7), true);
        } catch (_) {
          responseError(response, 401, "Session annonceur expirée.");
          return;
        }
        if (identity.uid !== requestId ||
            identity.role !== "advertiser_candidate" ||
            identity.advertiserRequestId !== requestId) {
          responseError(response, 403, "Accès au dossier non autorisé.");
          return;
        }

        const db = admin.firestore();
        const ref = db.collection("advertiserRequests").doc(requestId);
        const FieldValue = admin.firestore.FieldValue;
        const Timestamp = admin.firestore.Timestamp;
        try {
          const outcome = await db.runTransaction(async (transaction) => {
            const snapshot = await transaction.get(ref);
            if (!snapshot.exists) return "missing";
            const data = snapshot.data() || {};
            const correction = data.correctionRequest || {};
            // Une réponse perdue ne doit pas inscrire deux événements.
            if (data.status === "pending" &&
                correction.status === "resubmitted") {
              return "already_resubmitted";
            }
            const scopes = correction.scopes;
            if (data.status !== "changes_requested" ||
                correction.status !== "changes_requested" ||
                !Array.isArray(scopes) || scopes.length === 0 ||
                scopes.some((scope) => !SCOPE_NAMES.has(scope)) ||
                data.profileCompleted !== true ||
                data.establishmentCompleted !== true ||
                data.applicationCompleted !== true) {
              return "not_allowed";
            }
            const editLegal = scopes.includes("legal");
            if (editLegal !== body.legalAcceptance) {
              return "legal_mismatch";
            }
            const change = {
              "status": "pending",
              "review.status": "pending",
              "review.reason": "",
              "review.updatedAt": FieldValue.serverTimestamp(),
              "correctionRequest.status": "resubmitted",
              "correctionRequest.resubmittedAt": FieldValue.serverTimestamp(),
              "submittedAt": FieldValue.serverTimestamp(),
              "updatedAt": FieldValue.serverTimestamp(),
              "applicationHistory": FieldValue.arrayUnion({
                event: "resubmitted",
                actor: "advertiser",
                occurredAt: Timestamp.now(),
              }),
            };
            if (editLegal) {
              const version = typeof body.legalVersion === "string" ?
                body.legalVersion.trim() : "";
              const cgvVersion = typeof body.advertiserCgvVersion === "string" ?
                body.advertiserCgvVersion.trim() : "";
              if (!version || version.length > 80 || !cgvVersion ||
                  cgvVersion.length > 80) return "legal_mismatch";
              const metadataRef = db.collection("legalDocuments")
                  .doc("metadata");
              const cgvRef = db.collection("legalDocuments")
                  .doc("advertiserCgv");
              const metadataSnap = await transaction.get(metadataRef);
              const cgvSnap = await transaction.get(cgvRef);
              const metadata = metadataSnap.data() || {};
              const cgv = cgvSnap.data() || {};
              const currentVersion = String(metadata.legalVersion ||
                  metadata.version || metadata.activeVersion || "1.0");
              const currentCgv = String(cgv.version || "1.0");
              if (version !== currentVersion || cgvVersion !== currentCgv) {
                return "legal_outdated";
              }
              change.legalAcceptanceCompleted = true;
              change.acceptedDocuments = {
                cgu: true, privacy: true, rgpd: true, advertiserCgv: true,
                advertiserCgvVersion: currentCgv, version: currentVersion,
                acceptedAt: FieldValue.serverTimestamp(),
              };
              change.legalAcceptance = {
                version: currentVersion,
                packPath: String(metadata.packPath || ""),
                representativeDeclaration: true,
                advertiserCgvVersion: currentCgv,
                documents: {
                  cgu: true, privacy: true, rgpd: true, advertiserCgv: true,
                },
                acceptedAt: FieldValue.serverTimestamp(),
              };
            } else if (data.legalAcceptanceCompleted !== true) {
              return "legal_mismatch";
            }
            transaction.update(ref, change);
            return "updated";
          });
          if (outcome === "missing") {
            responseError(response, 404, "Dossier introuvable.");
          } else if (outcome === "not_allowed") {
            responseError(response, 409,
                "Aucune correction ouverte sur ce dossier.");
          } else if (outcome === "legal_mismatch" ||
              outcome === "legal_outdated") {
            responseError(response, 409,
                "Validations juridiques à actualiser.");
          } else {
            response.status(200).json({success: true, status: "pending"});
          }
        } catch (error) {
          console.error("Retransmission annonceur impossible", error);
          responseError(response, 500,
              "Transmission momentanément impossible.");
        }
      },
  );
}

module.exports = {registerAdvertiserCorrectionResubmit};
