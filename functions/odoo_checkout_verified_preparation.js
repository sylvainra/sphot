/* eslint-disable max-len, require-jsdoc, indent, object-curly-spacing, comma-dangle */
"use strict";

// Preparation commerciale serveur pour l'orchestrateur Odoo SPHOT.
// Aucun objet 'prepared', prix, ID Odoo ou statut fiscal provenant du body HTTP.
// Collection `odooCommercialVerifications`: CONFIDENTIELLE / ECRITURE SERVEUR
// UNIQUEMENT. Ne pas brancher ce service tant que les regles Firestore et
// l'alimentation des preuves Odoo ne sont pas verifiees en production.
// Aucun paiement, facture, droit commercial ou ecriture Firestore ici.

const crypto = require("node:crypto");
const CYCLE = /^[A-Z0-9_-]{3,64}$/;
const SIRET = /^\d{14}$/;
const ID = /^[A-Za-z0-9_-]{8,128}$/;
const SPOT_ID = /^[A-Za-z0-9_-]{1,128}$/;

function refuse(message, status = 409) {
  const error = new Error(message);
  error.httpStatus = status;
  error.code = "SPHOT_CHECKOUT_PREPARATION_REFUSED";
  return error;
}
function txt(x) {return typeof x === "string" ? x.trim() : "";}
function positive(x) {return Number.isSafeInteger(x) && x > 0;}
function sha(x) {return crypto.createHash("sha256").update(JSON.stringify(x)).digest("hex");}
function instant(value) {
  if (value instanceof Date && Number.isFinite(value.getTime())) {
    return value.toISOString();
  }
  if (value && typeof value.toDate === "function") {
    return instant(value.toDate());
  }
  if (value && Number.isInteger(value.seconds)) {
    return instant(new Date(value.seconds * 1000));
  }
  if (typeof value === "string" && /\d{4}-\d{2}-\d{2}T/.test(value) &&
      Number.isFinite(Date.parse(value))) {
    return new Date(value).toISOString();
  }
  return "";
}
function snapshotData(snapshot, label) {
  if (!snapshot?.exists || !snapshot.data || !snapshot.data()) {
    throw refuse(`${label} indisponible.`);
  }
  return snapshot.data();
}
function doc(db, collection, id) {
  return db.collection(collection).doc(id).get();
}
function validatedLegal(legalDoc, accepted, versionKey) {
  if (legalDoc.published === false || !txt(legalDoc.version) ||
      !Number.isSafeInteger(legalDoc.revision) || legalDoc.revision < 0 ||
      accepted.accepted !== true ||
      txt(accepted.version) !== txt(legalDoc.version) ||
      accepted.revision !== legalDoc.revision ||
      !instant(accepted.at)) {
    throw refuse("CGV non acceptées ou révision non concordante.");
  }
  return {version: txt(accepted.version), revision: accepted.revision,
    acceptedAt: instant(accepted.at), documentId: versionKey};
}
function acceptedFor(identity, subscription, legalDoc, documentId) {
  if (identity.market === "ADMIN") {
    const a = subscription.commercialCgvAcceptance || {};
    if (a.adminUid !== identity.uid || a.documentId !== documentId ||
        a.source !== "sphot_admin_cgv_server_acceptance_v1" ||
        a.testOnly !== false) {
      throw refuse("Acceptation CGV ADMIN phase 2 absente.");
    }
    return validatedLegal(legalDoc, {
      accepted: a.accepted, version: a.version,
      revision: a.revision, at: a.acceptedAt,
    }, documentId);
  }
  const a = identity.dossier.acceptedDocuments || {};
  const revisions = a.documentRevisions || {};
  if (a.advertiserCgv !== true ||
      a.advertiserCgvVersion !== txt(legalDoc.version) ||
      revisions.advertiserCgv !== legalDoc.revision) {
    throw refuse("Acceptation CGV PUBLICITAIRE absente ou périmée.");
  }
  return validatedLegal(legalDoc, {
    accepted: true, version: a.advertiserCgvVersion,
    revision: revisions.advertiserCgv,
    at: a.acceptedAt,
  }, documentId);
}
function adminStationCount(subscription, identity) {
  const ids = subscription.selectedRescueStationIds;
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > 10000 ||
      ids.some((id) => typeof id !== "string" || !SPOT_ID.test(id)) ||
      new Set(ids).size !== ids.length ||
      subscription.numberOfRescueStations !== ids.length ||
      subscription.billingCycle !== "annual" ||
      !["manager", "other"].includes(subscription.billingPayerRelation) ||
      !SIRET.test(txt(subscription.billingSiret)) ||
      !txt(identity.dossier.territoireId)) {
    throw refuse("Selection ou facturation ADMIN incomplete.");
  }
  // La preuve d'appartenance territoriale / statut surveille est etablie
  // plus bas via une attestation cote serveur, jamais via les cartes UI.
  return ids.slice().sort();
}
function taxAndBuyerEvidence(verification, identity, cycleKey, quote, legal, subscription) {
  const v = verification || {};
  if (v.market !== identity.market || v.requestId !== identity.requestId ||
      v.ownerUid !== identity.uid || v.cycleKey !== cycleKey ||
      v.status !== "verified" || v.testOnly !== false ||
      v.source !== "sphot_server_odoo_verified_v1" ||
      !txt(v.verifiedAt) || !txt(v.verifiedBy) ||
      !txt(v.buyerEvidenceId) || !txt(v.taxEvidenceId) ||
      !positive(v.partnerId) ||
      (identity.market === "ADVERTISER" && !positive(v.productId)) ||
      (identity.market === "ADMIN" &&
        (!Array.isArray(v.adminTierProductIds) ||
        v.adminTierProductIds.length !== 4 ||
        new Set(v.adminTierProductIds).size !== 4 ||
        v.adminTierProductIds.some((id) => !positive(id)))) ||
      v.pricingReference !== quote.pricingReference ||
      v.cgvVersion !== legal.version || v.cgvRevision !== legal.revision ||
      v.expectedUntaxedCents !== quote.payableExclTaxCents ||
      !Number.isSafeInteger(v.expectedTotalCents) ||
      v.expectedTotalCents < v.expectedUntaxedCents ||
      !/^[A-Z]{2}$/.test(txt(v.buyerCountry)) ||
      !txt(v.buyerLegalId) ||
      (identity.market === "ADMIN" &&
        (v.buyerCountry !== "FR" || !SIRET.test(txt(v.buyerSiret)) ||
         v.buyerSiret !== subscription.billingSiret))) {
    throw refuse("Preuves Odoo du payeur ou de fiscalite non rapprochees.");
  }
  return v;
}

async function prepareCheckoutFromFirestore({identity, db, admin,
  pricingApi, discountApi, odooDraftBuilder} = {}) {
  if (!identity || !db || !admin ||
      !["ADMIN", "ADVERTISER"].includes(identity.market) ||
      !ID.test(identity.requestId || "") ||
      !ID.test(identity.uid || "") ||
      !identity.dossier || typeof identity.dossier !== "object") {
    throw refuse("Identite serveur de commande invalide.", 403);
  }
  // Injectables UNIQUEMENT depuis le code serveur pour les tests. Le handler
  // HTTP ne doit pas accepter ces dependances ni l'objet 'prepared'.
  const pricing = pricingApi || require("./commercial_quote_pricing");
  const discounts = discountApi || require("./commercial_discounts");
  const bridge = odooDraftBuilder || require("./odoo_commercial_bridge").buildOdooDraft;
  const marketKey = identity.market === "ADMIN" ? "ADMIN" : "ADVERTISER_RADIUS";
  const legalId = identity.market === "ADMIN" ? "adminCgv" : "advertiserCgv";
  const [publishedSnap, legalSnap, discountSnap, subscriptionSnap,
    protectedAcceptanceSnap] = await Promise.all([
    doc(db, "commercialPricingMarkets", `FR_${marketKey}`),
    doc(db, "legalDocuments", legalId),
    doc(db, "commercialCustomerDiscounts",
        discounts.validateCustomer(marketKey, identity.uid)),
    identity.market === "ADMIN" ? doc(db, "subscriptions", identity.requestId) :
      Promise.resolve({exists: false}),
    // Les champs d'abonnement sont editables par les utilisateurs ; la preuve
    // contractuelle provient uniquement de la collection ECRITURE SERVEUR.
    identity.market === "ADMIN" ?
      doc(db, "odooAdminCgvAcceptanceEvidence", identity.uid) :
      Promise.resolve({exists: false}),
  ]);
  const published = pricing.publishedState(publishedSnap, marketKey);
  const legalDoc = snapshotData(legalSnap, "Document CGV");
  const subscription = identity.market === "ADMIN" ?
    snapshotData(subscriptionSnap, "Abonnement ADMIN") : null;
  const trustedSubscription = identity.market === "ADMIN" ? {
    ...subscription,
    commercialCgvAcceptance: protectedAcceptanceSnap.exists ?
      protectedAcceptanceSnap.data() : null,
  } : subscription;
  const legal = acceptedFor(identity, trustedSubscription, legalDoc, legalId);
  let quote;
  let choices;
  if (identity.market === "ADMIN") {
    const ids = adminStationCount(subscription, identity);
    quote = pricing.adminQuote(published, ids.length);
    if (subscription.publishedPricingReference !== quote.pricingReference ||
        subscription.publishedPricingVersion !== quote.version) {
      throw refuse("Tarif ADMIN modifie depuis la selection.");
    }
    choices = {stationIds: ids};
  } else {
    const data = identity.dossier;
    if (data.status !== "approved" || data.campaignActivated === true ||
        data.advertisingSpotCompleted !== true ||
        data.diffusionCompleted !== true ||
        data.planningCompleted !== true) {
      throw refuse("Dossier annonceur non pret pour la commande.");
    }
    const territory = txt(data.advertisingTerritory?.level);
    const offer = txt(data.diffusion?.visibilityType);
    const duration = txt(data.planning?.durationLabel);
    quote = pricing.advertiserQuote(published, territory, offer, duration);
    choices = {territory, offer, duration};
  }
  const percent = discountSnap.exists ?
    discounts.validatePercent(discountSnap.data().percent) : 0;
  Object.assign(quote, discounts.computeDiscountCents(quote.amountExclTax, percent));
  // Les cycles doivent etre attribues par le backend commercial. En l'absence
  // d'un cycle contractuel reel, aucune commande Odoo ne peut partir.
  const cycleKey = identity.market === "ADMIN" ?
    txt(subscription.commercialCycleKey) : txt(identity.dossier.commercialCycleKey);
  if (!CYCLE.test(cycleKey)) throw refuse("Cycle contractuel non valide.");
  const verificationSnap = await doc(db, "odooCommercialVerifications",
      `${identity.market}_${identity.requestId}_${cycleKey}`);
  const verification = snapshotData(verificationSnap, "Validation Odoo");
  const v = taxAndBuyerEvidence(verification, identity, cycleKey, quote,
      legal, subscription);
  if (v.choicesHash !== sha(choices)) {
    throw refuse("Choix commerciaux modifies depuis la verification serveur.");
  }
  // Les selecteurs de postes sont recus du dossier, mais la verification
  // territoriale reste obligatoirement certifiee par la couche serveur.
  if (identity.market === "ADMIN" &&
      (v.stationIdsHash !== sha(choices.stationIds) ||
       v.territoireId !== identity.dossier.territoireId)) {
    throw refuse("Postes ADMIN non certifies pour le territoire.");
  }
  const reference = `SPHOT-${identity.market === "ADMIN" ? "ADM" : "PUB"}-` +
    sha([identity.market, identity.requestId, cycleKey]).slice(0, 24).toUpperCase();
  const draft = bridge({quote, partnerId: v.partnerId,
    productIds: identity.market === "ADMIN" ?
      {adminTiers: v.adminTierProductIds} : {advertiser: v.productId},
    sphotReference: reference});
  if (draft.expectedUntaxedCents !== quote.payableExclTaxCents ||
      draft.values?.client_order_ref !== reference ||
      draft.values?.origin !== `SPHOT ${quote.pricingReference}`) {
    throw refuse("Brouillon Odoo non conforme au devis serveur.");
  }
  const orderValues = draft.values;
  const fingerprint = sha({reference, cycleKey, choices, orderValues,
    legal, pricingReference: quote.pricingReference,
    totalTtc: v.expectedTotalCents, buyerEvidenceId: v.buyerEvidenceId,
    taxEvidenceId: v.taxEvidenceId});
  return Object.freeze({
    source: "SPHOT_SERVER_VERIFIED_CHECKOUT_V1", verified: true,
    testOnly: false, market: identity.market, ownerUid: identity.uid,
    requestId: identity.requestId, cycleKey, reference, fingerprint,
    orderValues, expectedUntaxedCents: quote.payableExclTaxCents,
    expectedTotalCents: v.expectedTotalCents,
    verification: {
      source: "sphot_server_firestore_verified",
      cgvVersion: legal.version,
      cgvAcceptedAt: legal.acceptedAt,
      buyerEvidenceId: v.buyerEvidenceId,
      taxEvidenceId: v.taxEvidenceId,
      pricingReference: quote.pricingReference,
    },
  });
}

module.exports = {prepareCheckoutFromFirestore, acceptedFor,
  adminStationCount, taxAndBuyerEvidence};
