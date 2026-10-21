"use strict";

// Decisions Super Admin PHASE 1 et revue des propositions visuelles PHASE 2.
// Aucune donnee de decision / d'historique n'est acceptee depuis le navigateur.
const CORRECTION_SCOPES = new Set([
  "identity", "establishment", "location", "visual", "destination", "legal",
]);

/**
 * Génère une erreur applicative contrôlée.
 * @param {number} status Code de la réponse.
 * @param {string} message Message utilisable par l'interface.
 * @return {Error} Erreur annotée.
 */
function refusal(status, message) {
  const err = new Error(message);
  err.httpStatus = status;
  return err;
}

/**
 * Normalise une valeur texte fournie au serveur.
 * @param {*} value Valeur brute.
 * @return {string} Texte.
 */
function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}

/**
 * Récupère une map existante, sans faire confiance au corps de la requête.
 * @param {*} value Valeur Firestore.
 * @return {Object} Copie de la map.
 */
function map(value) {
  return value && typeof value === "object" && !Array.isArray(value) ?
    {...value} : {};
}

/**
 * Prépare une décision uniquement à partir de l'état du dossier en base.
 * @param {Object} data Dossier relu par transaction.
 * @param {Object} command Commande limitée aux choix humains.
 * @param {Object} fv FieldValue Admin Firebase.
 * @param {Object} Timestamp Timestamp Admin Firebase.
 * @return {Object} Champs et historiques à écrire.
 */
function buildDecisionUpdate(data, command, fv, Timestamp) {
  const decision = clean(command.decision);
  if (!["approved", "changes_requested", "rejected"].includes(decision)) {
    throw refusal(400, "Décision inconnue.");
  }
  const oldStatus = clean(data.status).toLowerCase();
  const asset = map(data.assetChangeRequest);
  const isAssetReview = oldStatus === "approved" &&
    asset.status === "submitted";
  if (!isAssetReview && oldStatus !== "pending") {
    throw refusal(409, "Cette candidature n'est plus en attente.");
  }
  const reason = clean(command.reason);
  if (decision !== "approved" && (reason.length === 0 ||
      reason.length > 2000)) {
    throw refusal(400, "Motif obligatoire (2000 caractères maximum).");
  }
  const scopes = command.scopes === undefined ? [] : command.scopes;
  if (!Array.isArray(scopes) || scopes.some((s) =>
    typeof s !== "string" || !CORRECTION_SCOPES.has(s)) ||
    new Set(scopes).size !== scopes.length) {
    throw refusal(400, "Rubriques de correction invalides.");
  }
  if (decision === "changes_requested" && !isAssetReview &&
      scopes.length === 0) {
    throw refusal(400, "Sélectionnez une rubrique à corriger.");
  }
  if ((decision !== "changes_requested" || isAssetReview) &&
      scopes.length > 0) {
    throw refusal(400, "Rubriques interdites pour cette décision.");
  }
  const recipient = clean(data.contactEmail || data.email);
  if (!recipient || !recipient.includes("@")) {
    throw refusal(409, "Adresse de contact absente du dossier.");
  }
  const now = fv.serverTimestamp();
  const updated = {
    status: isAssetReview ? "approved" : decision,
    updatedAt: now,
  };
  // A PHASE 2 decision must not replace the PHASE 1 approval record.
  if (!isAssetReview) {
    updated.review = {
      status: decision,
      reason,
      reviewedBy: "super_admin",
      reviewedAt: now,
      ...(scopes.length > 0 ? {correctionScopes: scopes} : {}),
    };
  }
  if (decision === "approved") {
    const proposedVisual = isAssetReview ?
      map(asset.proposedVisual || data.proposedVisual) :
      map(data.proposedVisual);
    const proposedLocation = isAssetReview ?
      map(asset.proposedLocation || data.applicantLocation) :
      map(data.applicantLocation);
    if (isAssetReview) {
      const url = clean(proposedVisual.url);
      if (!url.startsWith("https://")) {
        throw refusal(409, "Visuel HTTPS absent ou invalide.");
      }
      const lat = proposedLocation.latitude;
      const lng = proposedLocation.longitude;
      if (typeof lat !== "number" || typeof lng !== "number" ||
          !Number.isFinite(lat) || !Number.isFinite(lng) ||
          Math.abs(lat) > 90 || Math.abs(lng) > 180) {
        throw refusal(409, "Localisation proposée invalide.");
      }
      const oldApproved = map(data.approvedApplication);
      const oldSpot = map(data.advertisingSpot);
      updated.approvedApplication = {
        ...oldApproved, location: proposedLocation, visual: proposedVisual,
        approvedAt: now,
      };
      updated.advertisingSpot = {
        ...oldSpot, bannerUrl: url,
        bannerFileName: proposedVisual.fileName ?? null,
        bannerExtension: proposedVisual.extension ?? null,
        bannerMimeType: proposedVisual.mimeType ?? null,
        bannerFileSizeBytes: proposedVisual.fileSizeBytes ?? null,
        bannerWidth: proposedVisual.width ?? null,
        bannerHeight: proposedVisual.height ?? null,
        latitude: lat, longitude: lng,
      };
      // Keep the initial PHASE 1 applicantLocation as declared.
      updated.assetChangeRequest = {
        ...asset, proposedVisual, proposedLocation,
        status: "approved", reviewedAt: now,
      };
      updated.assetChangeHistory = fv.arrayUnion({
        decision, submittedAt: asset.submittedAt || null,
        decidedAt: Timestamp.now(), decidedBy: "super_admin",
        previousVisualUrl: clean(map(oldApproved.visual).url ||
          oldSpot.bannerUrl),
        previousLocation: Object.keys(map(oldApproved.location)).length > 0 ?
          map(oldApproved.location) :
          {latitude: oldSpot.latitude ?? null,
            longitude: oldSpot.longitude ?? null},
        proposedVisualUrl: url, proposedLocation, reason,
      });
    } else {
      updated.approvedApplication = {
        location: proposedLocation, visual: proposedVisual,
        destinationUrl: data.destinationUrl || "", approvedAt: now,
      };
      updated.approvalEmail = {status: "pending", recipient, updatedAt: now};
      updated.approvedAt = now;
    }
  } else if (decision === "changes_requested") {
    updated.changeRequestEmail = {
      status: "pending", recipient, reason,
      ...(scopes.length > 0 ? {correctionScopes: scopes} : {}),
      updatedAt: now,
    };
    if (isAssetReview) {
      updated.assetChangeRequest = {
        ...asset, status: "changes_requested", reason,
        reviewedAt: now,
      };
    } else {
      updated.correctionRequest = {
        status: "changes_requested", scopes, reason, requestedAt: now,
      };
    }
  } else {
    updated.rejectionEmail = {
      status: "pending", recipient, reason, updatedAt: now,
    };
    if (isAssetReview) {
      updated.assetChangeRequest = {
        ...asset, status: "rejected", reason, reviewedAt: now,
      };
    }
  }
  if (isAssetReview && decision !== "approved") {
    const approved = map(data.approvedApplication);
    const oldSpot = map(data.advertisingSpot);
    const proposedVisual = map(asset.proposedVisual || data.proposedVisual);
    const proposedLocation = map(asset.proposedLocation ||
      data.applicantLocation);
    updated.assetChangeHistory = fv.arrayUnion({
      decision, submittedAt: asset.submittedAt || null,
      decidedAt: Timestamp.now(), decidedBy: "super_admin",
      previousVisualUrl: clean(map(approved.visual).url || oldSpot.bannerUrl),
      previousLocation: Object.keys(map(approved.location)).length > 0 ?
        map(approved.location) :
        {latitude: oldSpot.latitude ?? null,
          longitude: oldSpot.longitude ?? null},
      proposedVisualUrl: clean(proposedVisual.url),
      proposedLocation, reason,
    });
  }
  if (!isAssetReview) {
    updated.applicationHistory = fv.arrayUnion({
      event: decision, actor: "super_admin", occurredAt: Timestamp.now(),
      reason, ...(scopes.length > 0 ? {correctionScopes: scopes} : {}),
    });
  }
  return updated;
}

/**
 * Enregistre les décisions de façon atomique après contrôle de session.
 * @param {Object} deps Dépendances injectées.
 * @return {Function} Fonction HTTPS Firebase.
 */
function registerAdvertiserReviewDecision({
  admin, crypto, onRequest, checkSuperAdminSession,
}) {
  return onRequest(
      {region: "us-central1", cors: true, cpu: 1, memory: "256MiB"},
      async (req, res) => {
        if (req.method !== "POST") {
          res.status(405).json({success: false, error: "Méthode refusée."});
          return;
        }
        const token = clean((req.headers.authorization || "")
            .replace(/^Bearer /, ""));
        try {
          await checkSuperAdminSession(admin, crypto, token);
        } catch (_) {
          res.status(401).json({success: false,
            error: "Session Super Admin expirée."});
          return;
        }
        const body = req.body || {};
        if (Object.keys(body).some((key) =>
          !["requestId", "action", "decision", "reason", "scopes"]
              .includes(key))) {
          res.status(400).json({success: false,
            error: "Champs non autorisés."});
          return;
        }
        const requestId = clean(body.requestId);
        if (!/^[a-zA-Z0-9_-]{8,128}$/.test(requestId)) {
          res.status(400).json({success: false,
            error: "Identifiant de candidature invalide."});
          return;
        }
        const action = clean(body.action);
        if (action !== "review" && action !== "authorizeAsset") {
          res.status(400).json({success: false,
            error: "Action inconnue."});
          return;
        }
        try {
          const ref = admin.firestore().collection("advertiserRequests")
              .doc(requestId);
          await admin.firestore().runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            if (!snap.exists) throw refusal(404, "Dossier introuvable.");
            const data = snap.data() || {};
            if (action === "authorizeAsset") {
              if (Object.keys(body).some((k) =>
                !["requestId", "action"].includes(k))) {
                throw refusal(400, "Champs non autorisés.");
              }
              const current = map(data.assetChangeRequest);
              if (data.status !== "approved" ||
                  current.status !== "submitted") {
                throw refusal(409, "Proposition non soumise.");
              }
              tx.update(ref, {
                assetChangeRequest: {
                  ...current, status: "authorized",
                  authorizedAt: admin.firestore.FieldValue.serverTimestamp(),
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            } else {
              tx.update(ref, buildDecisionUpdate(data, body,
                  admin.firestore.FieldValue, admin.firestore.Timestamp));
            }
          });
          res.status(200).json({success: true});
        } catch (error) {
          if (!error.httpStatus) {
            console.error("Revue annonceur impossible", error);
          }
          res.status(error.httpStatus || 500).json({success: false,
            error: error.httpStatus ? error.message :
              "Opération momentanément impossible."});
        }
      },
  );
}

module.exports = {buildDecisionUpdate, registerAdvertiserReviewDecision};
