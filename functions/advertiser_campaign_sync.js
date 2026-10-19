"use strict";

/**
 * Applique un changement de visuel/position approuvé aux campagnes PUBLIQUES
 * déjà reliées au dossier annonceur, sans création, activation, changement
 * d'offre, de période ou de tarification.
 */
const crypto = require("crypto");

function stringValue(value) {
  return typeof value === "string" ? value.trim() : "";
}

function isHttpsUrl(value) {
  try {
    const parsed = new URL(stringValue(value));
    return parsed.protocol === "https:" && parsed.hostname.length > 0;
  } catch (_) {
    return false;
  }
}

function approvedAssetPatch(beforeData, afterData) {
  const before = beforeData || {};
  const after = afterData || {};
  const previous = before.assetChangeRequest || {};
  const current = after.assetChangeRequest || {};

  if (stringValue(before.status).toLowerCase() !== "approved" ||
      stringValue(after.status).toLowerCase() !== "approved" ||
      previous.status !== "submitted" ||
      current.status !== "approved") {
    return null;
  }

  const visual = current.proposedVisual || after.proposedVisual || {};
  const bannerUrl = stringValue(visual.url);
  if (!isHttpsUrl(bannerUrl)) return null;

  const location = current.proposedLocation || after.applicantLocation || {};
  const latitude = location.latitude;
  const longitude = location.longitude;
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      latitude < -90 || latitude > 90 ||
      longitude < -180 || longitude > 180) {
    return null;
  }

  return {bannerUrl, centerLat: latitude, centerLng: longitude};
}

function sameSubmission(left, right) {
  if (!left || !right) return false;
  if (typeof left.toMillis === "function" &&
      typeof right.toMillis === "function") {
    return left.toMillis() === right.toMillis();
  }
  return left === right;
}

function registerAdvertiserCampaignSync({admin, onDocumentUpdated}) {
  return onDocumentUpdated(
      {
        document: "advertiserRequests/{requestId}",
        region: "europe-west1",
        cpu: 1,
        memory: "256MiB",
        retry: true,
      },
      async (event) => {
        const before = event.data.before.data() || {};
        const after = event.data.after.data() || {};
        const patch = approvedAssetPatch(before, after);
        if (!patch) return;

        const requestId = event.params.requestId;
        const db = admin.firestore();
        const requestsRef = event.data.after.ref;
        const campaigns = db.collection("adRequests");

        // Association explicite obligatoire : ni email, ni nom commercial,
        // ni distance géographique ne déterminent une campagne à modifier.
        const query = await campaigns
            .where("advertiserRequestId", "==", requestId)
            .limit(50).get();
        const targets = new Map();
        for (const doc of query.docs) targets.set(doc.ref.path, doc.ref);

        // Compatibilité des campagnes qui utilisent l'ID de dossier
        // comme ID de campagne.
        const directRef = campaigns.doc(requestId);
        const directSnapshot = await directRef.get();
        if (directSnapshot.exists) {
          targets.set(directRef.path, directRef);
        }

        const refs = [...targets.values()];
        const submission = after.assetChangeRequest.submittedAt;
        const eventKey = crypto.createHash("sha256")
            .update(String(event.id)).digest("hex");

        await db.runTransaction(async (tx) => {
          const currentRequest = await tx.get(requestsRef);
          const currentData = currentRequest.data() || {};
          const currentChange = currentData.assetChangeRequest || {};
          if (currentData.status !== "approved" ||
              currentChange.status !== "approved" ||
              !sameSubmission(currentChange.submittedAt, submission)) {
            return;
          }

          // Toutes les lectures transactionnelles avant les écritures.
          const docs = [];
          for (const ref of refs) {
            docs.push(await tx.get(ref));
          }

          let updated = 0;
          for (const doc of docs) {
            if (!doc.exists) continue;
            const campaign = doc.data() || {};
            if (campaign.status !== "active") continue;
            if (doc.id !== requestId &&
                campaign.advertiserRequestId !== requestId) continue;
            if (campaign.lastApprovedAssetEventId === eventKey) continue;

            const change = {
              bannerUrl: patch.bannerUrl,
              lastApprovedAssetEventId: eventKey,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (campaign.broadcastType === "local") {
              change.centerLat = patch.centerLat;
              change.centerLng = patch.centerLng;
            }
            tx.update(doc.ref, change);

            // Historiser le remplacement sans écraser l'ancien visuel.
            const history = doc.ref.collection("approvedAssetChanges")
                .doc(eventKey);
            tx.set(history, {
              advertiserRequestId: requestId,
              previousBannerUrl: stringValue(campaign.bannerUrl),
              approvedBannerUrl: patch.bannerUrl,
              previousCenterLat: campaign.centerLat ?? null,
              previousCenterLng: campaign.centerLng ?? null,
              approvedCenterLat: change.centerLat ?? null,
              approvedCenterLng: change.centerLng ?? null,
              appliedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            updated++;
          }

          tx.update(requestsRef, {
            "assetChangeRequest.syncStatus": updated > 0 ?
              "applied" : (refs.length > 0 ? "no_active_campaign" : "unlinked"),
            "assetChangeRequest.syncedCampaignCount": updated,
            "assetChangeRequest.lastSyncAt":
              admin.firestore.FieldValue.serverTimestamp(),
          });
        });
      },
  );
}

module.exports = {
  approvedAssetPatch,
  registerAdvertiserCampaignSync,
};
