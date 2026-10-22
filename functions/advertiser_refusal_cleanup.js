"use strict";

// Un refus de candidature PHASE 1 est suivi d'une suppression définitive.
// La suppression n'est déclenchée qu'après confirmation d'envoi du mail.
// Le marqueur explicite évite d'effacer les refus antérieurs au déploiement.
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{8,128}$/;
const STORAGE_BUCKET = "sphot-ab80b.firebasestorage.app";

/** @return {boolean} Refus initial prêt à être supprimé. */
function eligibleForCleanup(data) {
  return data && data.status === "rejected" &&
    data.purgeAfterRejectionEmail === true &&
    data.review && data.review.status === "rejected" &&
    data.rejectionEmail && data.rejectionEmail.status === "sent" &&
    data.rejectionEmail.sentAt != null;
}

/**
 * Supprime uniquement les ressources appartenant au dossier refusé.
 * L'ordre permet de reprendre après une erreur transitoire : le document
 * Firestore, nécessaire aux vérifications, est supprimé en dernier.
 *
 * @param {Object} admin Firebase Admin SDK.
 * @param {string} requestId Identifiant exact du dossier.
 * @return {Promise<boolean>} Vrai si le dossier a été supprimé.
 */
async function purgeRejectedAdvertiserRequest(admin, requestId) {
  if (!REQUEST_ID_PATTERN.test(requestId)) {
    throw new Error("Identifiant de candidature invalide pour suppression.");
  }
  const reference = admin.firestore().collection("advertiserRequests")
      .doc(requestId);
  const snapshot = await reference.get();
  if (!snapshot.exists || !eligibleForCleanup(snapshot.data())) return false;
  const data = snapshot.data();
  if (data.uid !== requestId) {
    throw new Error(
        "Identifiant du dossier incohérent : suppression bloquée.",
    );
  }

  // Le compte créé pour une candidature est anonyme et porte le même UID.
  // Il ne faut jamais effacer un compte ayant acquis une identité pérenne.
  let account;
  try {
    account = await admin.auth().getUser(requestId);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
  if (account && (account.email ||
      (account.providerData || []).length > 0)) {
    throw new Error("Compte non anonyme : suppression automatique bloquée.");
  }

  const prefix = `advertiser_requests/${requestId}/`;
  const bucket = admin.storage().bucket(STORAGE_BUCKET);
  const [files] = await bucket.getFiles({prefix});
  for (const file of files) {
    if (!file.name.startsWith(prefix)) {
      throw new Error("Fichier hors du dossier ciblé : suppression bloquée.");
    }
    await file.delete({ignoreNotFound: true});
  }

  if (account) {
    try {
      await admin.auth().deleteUser(requestId);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
  }
  // Si une autre opération a modifié le dossier pendant le nettoyage,
  // ne pas supprimer aveuglément un état qui n'est plus un refus initial.
  const fresh = await reference.get();
  if (!fresh.exists || !eligibleForCleanup(fresh.data())) return false;
  await admin.firestore().recursiveDelete(reference);
  return true;
}

/**
 * @param {Object} dependencies Dépendances Cloud Functions injectées.
 * @return {Function} Trigger de nettoyage des candidatures refusées.
 */
function registerAdvertiserRefusalCleanup({admin, onDocumentUpdated}) {
  return onDocumentUpdated({
    document: "advertiserRequests/{requestId}",
    region: "europe-west1",
    retry: true,
    cpu: 1,
    memory: "256MiB",
  }, async (event) => {
    const after = event.data && event.data.after &&
      event.data.after.data();
    if (!eligibleForCleanup(after)) return;
    const requestId = event.params && event.params.requestId;
    if (!REQUEST_ID_PATTERN.test(requestId || "")) return;
    await purgeRejectedAdvertiserRequest(admin, requestId);
  });
}

module.exports = {
  eligibleForCleanup,
  purgeRejectedAdvertiserRequest,
  registerAdvertiserRefusalCleanup,
};
