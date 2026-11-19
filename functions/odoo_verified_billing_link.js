"use strict";

// SPHOT / Odoo - Rapprochement comptable interne des dossiers Firestore.
// Aucun point d'entree HTTP, aucun export Firebase, aucun deploiement.
// Ne cree aucune commande, facture, transaction ou activation de droits.
// Le lien est pose SEULEMENT apres la relecture de la facture Odoo par
// confirmVerifiedInvoiceFromServer (facture comptabilisee et unique).
//
// TEST LOCAL : l'orchestration est desactivee par defaut et exige
// FIRESTORE_EMULATOR_HOST + base Odoo clone neutralisee + flag explicite.
// La projection transactionnelle est testable en memoire, sans production.

const {resolveOdooCheckoutIdentity} = require("./odoo_checkout_identity");
const {prepareCheckoutFromFirestore} =
    require("./odoo_checkout_verified_preparation");
const {assertServerPreparation, sameIntent} =
    require("./odoo_checkout_orchestrator");
const {confirmVerifiedInvoiceFromServer} =
    require("./odoo_verified_invoice_wiring");

const CLONE = "sphot_checkout_clone_neutral_20261118";

function refuser(message) {
  const erreur = new Error(message);
  erreur.code = "SPHOT_ODOO_FIRESTORE_LINK_REFUSED";
  erreur.httpStatus = 409;
  return erreur;
}
function texte(x) {
  return typeof x === "string" ? x.trim() : "";
}
function entier(x) {
  return Number.isSafeInteger(x) && x > 0;
}
function idCycle(identity, prepared) {
  return identity.market + "_" + identity.requestId + "_" +
      prepared.cycleKey;
}
function validerRecu(identity, prepared, recu) {
  assertServerPreparation(identity, prepared);
  if (!recu || !["created", "existing"].includes(recu.outcome) ||
      recu.market !== identity.market ||
      recu.reference !== prepared.reference ||
      recu.cycleKey !== prepared.cycleKey ||
      !entier(recu.orderId) || !texte(recu.orderNumber) ||
      !entier(recu.invoiceId) || !texte(recu.invoiceNumber) ||
      recu.invoiceState !== "posted" ||
      recu.amountUntaxedCents !== prepared.expectedUntaxedCents ||
      recu.amountTotalCents !== prepared.expectedTotalCents ||
      recu.paymentStatus !== "unverified" ||
      recu.activatesCommercialRights !== false ||
      recu.requiresSeparatePaymentEvidence !== true) {
    throw refuser("Facture Odoo non verifiee pour le dossier SPHOT.");
  }
}

function champsImmuables(identity, prepared, recu) {
  return {
    ownerUid: identity.uid,
    market: identity.market,
    cycleKey: prepared.cycleKey,
    orderReference: prepared.reference,
    orderFingerprint: prepared.fingerprint,
    orderId: recu.orderId,
    orderNumber: recu.orderNumber,
    invoiceId: recu.invoiceId,
    invoiceNumber: recu.invoiceNumber,
    invoiceState: "posted",
    amountUntaxedCents: prepared.expectedUntaxedCents,
    amountTotalCents: prepared.expectedTotalCents,
    currency: "EUR",
    testOnly: false,
    paymentStatus: "unverified",
    activatesCommercialRights: false,
  };
}
function memeLien(enregistre, attendu) {
  if (!enregistre || typeof enregistre !== "object" ||
      Array.isArray(enregistre)) return false;
  return Object.keys(attendu).every(cle =>
    enregistre[cle] === attendu[cle]);
}
function verifierIntent(intent, identity, prepared, recu) {
  if (!sameIntent(intent, identity, prepared) ||
      intent.status !== "draft_created" ||
      intent.orderNumber !== recu.orderNumber ||
      intent.paymentStatus !== "unverified" ||
      intent.activatesCommercialRights !== false ||
      (intent.invoiceId !== undefined &&
       intent.invoiceId !== recu.invoiceId) ||
      (intent.invoiceNumber !== undefined &&
       intent.invoiceNumber !== recu.invoiceNumber)) {
    throw refuser("Reservation de commande ou facture differente.");
  }
}

async function enregistrerLienFactureVerifie({
  db, identity, prepared, recu, horodatage,
} = {}) {
  if (!db || typeof db.runTransaction !== "function" ||
      typeof horodatage !== "function" ||
      !identity || !prepared) {
    throw refuser("Stockage Firestore interne indisponible.");
  }
  validerRecu(identity, prepared, recu);
  const base = champsImmuables(identity, prepared, recu);
  const intentRef = db.collection("odooCheckoutIntents")
      .doc(idCycle(identity, prepared));
  const factureRef = identity.market === "ADMIN" ?
    db.collection("adminOdooCycles").doc(prepared.reference) :
    db.collection("advertiserRequests").doc(identity.requestId);
  const subscriptionRef = identity.market === "ADMIN" ?
    db.collection("subscriptions").doc(identity.requestId) : null;
  const admin = identity.market === "ADMIN";

  return db.runTransaction(async tx => {
    // Firestore impose toutes les lectures AVANT les ecritures.
    const intentSnap = await tx.get(intentRef);
    const linkedSnap = await tx.get(factureRef);
    const subscriptionSnap = admin ?
      await tx.get(subscriptionRef) : null;

    if (!intentSnap.exists) {
      throw refuser("Reservation commerciale Firestore absente.");
    }
    const intent = intentSnap.data() || {};
    verifierIntent(intent, identity, prepared, recu);

    const dejaLie = admin ?
      (linkedSnap.exists ? linkedSnap.data() || {} : null) :
      (linkedSnap.exists ?
        (linkedSnap.data() || {}).odooBilling || null : null);
    const attendu = admin ? {...base, adminUid: identity.uid} : base;

    if (dejaLie && !memeLien(dejaLie, attendu)) {
      throw refuser("Un autre rattachement comptable existe deja.");
    }
    if (admin) {
      if (!subscriptionSnap?.exists) {
        throw refuser("Abonnement ADMIN inexistant.");
      }
      const subscription = subscriptionSnap.data() || {};
      if (subscription.adminUid &&
          subscription.adminUid !== identity.uid) {
        throw refuser("Abonnement ADMIN attribue a un autre utilisateur.");
      }
      if (subscription.odooAdminCycleRef &&
          subscription.odooAdminCycleRef !== prepared.reference) {
        // Les renouvellements restent traites separement.
        throw refuser("Autre cycle de facturation ADMIN deja rattache.");
      }
    } else {
      if (!linkedSnap.exists) {
        throw refuser("Dossier PUBLICITAIRE introuvable.");
      }
      const dossier = linkedSnap.data() || {};
      if (dossier.firebaseUid &&
          dossier.firebaseUid !== identity.uid) {
        throw refuser("Dossier PUBLICITAIRE appartenant a un autre compte.");
      }
      if (dossier.status !== "approved" ||
          dossier.campaignActivated === true) {
        throw refuser("Dossier annonceur modifie avant rapprochement.");
      }
    }

    const intentLie = intent.invoiceId === recu.invoiceId &&
      intent.invoiceNumber === recu.invoiceNumber &&
      intent.invoiceState === "posted" &&
      intent.activatesCommercialRights === false &&
      intent.paymentStatus === "unverified";

    if (dejaLie && intentLie &&
        (admin ? subscriptionSnap.data()?.odooAdminCycleRef ===
          prepared.reference : true)) {
      return {outcome: "existing", market: identity.market,
        reference: prepared.reference, invoiceId: recu.invoiceId,
        activatesCommercialRights: false, paymentStatus: "unverified"};
    }

    const horodatageServeur = horodatage();
    if (!dejaLie) {
      const link = {...attendu, linkedAt: horodatageServeur};
      if (admin) tx.create(factureRef, link);
      else tx.update(factureRef, {odooBilling: link});
    }
    if (admin && subscriptionSnap.data()?.odooAdminCycleRef !==
        prepared.reference) {
      tx.update(subscriptionRef, {odooAdminCycleRef: prepared.reference});
    }
    if (!intentLie) {
      tx.update(intentRef, {
        invoiceId: recu.invoiceId,
        invoiceNumber: recu.invoiceNumber,
        invoiceState: "posted",
        paymentStatus: "unverified",
        activatesCommercialRights: false,
        invoiceLinkedAt: horodatageServeur,
      });
    }
    return {outcome: "linked", market: identity.market,
      reference: prepared.reference, invoiceId: recu.invoiceId,
      activatesCommercialRights: false, paymentStatus: "unverified"};
  });
}

/**
 * Orchestration TEST non publiee : refus par defaut.
 * Le seul mode autorise pour les premiers essais de persistance utilise
 * Firebase Emulator et le clone Odoo ; pas de Firestore reel.
 */
async function lierFactureTestDepuisServeur({
  admin, authorization, market, requestId, odooClient,
  environment = process.env,
} = {}) {
  if (!environment ||
      environment.SPHOT_ENABLE_ODOO_FIRESTORE_LINK_TEST !== "true" ||
      !texte(environment.FIRESTORE_EMULATOR_HOST) ||
      environment.SPHOT_ODOO_DATABASE !== CLONE) {
    throw refuser("Rattachement Firestore desactive hors tests isoles.");
  }
  if (!admin || typeof admin.firestore !== "function" ||
      !odooClient || typeof odooClient.call !== "function") {
    throw refuser("Services de facturation indisponibles.");
  }
  const recu = await confirmVerifiedInvoiceFromServer({
    admin, authorization, market, requestId, odooClient,
  });
  const identity = await resolveOdooCheckoutIdentity({
    admin, authorization, market, requestId,
  });
  const db = admin.firestore();
  const prepared = await prepareCheckoutFromFirestore({
    identity, db, admin,
  });
  return enregistrerLienFactureVerifie({
    db, identity, prepared, recu,
    horodatage: () => admin.firestore.FieldValue.serverTimestamp(),
  });
}

module.exports = {
  enregistrerLienFactureVerifie,
  lierFactureTestDepuisServeur,
  CLONE,
};
