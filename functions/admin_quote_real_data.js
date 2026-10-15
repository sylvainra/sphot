/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {adminQuote, publishedState} = require("./commercial_quote_pricing");

// Lecture des VRAIES collections SPHOT, exclusivement côté serveur.
// Cette fonction ne prépare qu'un brouillon chiffré, sans statut de
// vérification juridique, aucune émission, aucun numéro DV ni écriture.
// Les collections admins/adminRequests/subscriptions/spots ont actuellement
// des écritures clientes trop larges : ne JAMAIS inférer de ce brouillon
// une autorisation juridique/fiscale ou le droit de créer un devis.
function blocked(code) {
  return Object.freeze({status: "blocked", reasonCodes: [code]});
}
function string(value) {
  return typeof value === "string" ? value.trim() : "";
}
function safeId(value) {
  return /^[A-Za-z0-9_-]{1,220}$/.test(string(value));
}
function read(snapshot) {
  return snapshot && snapshot.exists ? snapshot.data() || {} : null;
}
function role(value) {
  return string(value).toUpperCase();
}
function country(raw) {
  return ["FR", "FRA", "FRANCE"].includes(role(raw)) ? "FR" : string(raw);
}
function spotName(data) {
  return string(data.nomSphot) || string(data.nomSecours) ||
      string(data.name) || string(data.nom) ||
      string(data.title);
}
function isRescueStation(data) {
  return data.isPosteSecours === true ||
      role(data.typeSphot).includes("POSTE DE SECOURS");
}
function nonEmpty(value, fallback) {
  return string(value) || string(fallback);
}

// L'appelant ne peut fournir QUE le jeton Firebase. Ni uid, ni territoire,
// ni prix, ni listes de postes externes ne sont acceptés comme autorité.
// En production, cet adaptateur sera exécuté par un endpoint qui valide
// sa propre session et dont la réponse n'autorise jamais l'émission.
async function loadRealAdminQuoteDraft({auth, db, idToken} = {}) {
  if (!auth || typeof auth.verifyIdToken !== "function" ||
      !db || typeof db.collection !== "function" ||
      !string(idToken)) {
    return blocked("SERVER_AUTH_UNAVAILABLE");
  }

  let session;
  try {
    // checkRevoked=true : refuse aussi les sessions administrateur révoquées.
    session = await auth.verifyIdToken(idToken, true);
  } catch (_) {
    return blocked("INVALID_ADMIN_SESSION");
  }
  const uid = string(session && session.uid);
  const territory = string(session && session.territoireId);
  if (!safeId(uid) || !safeId(territory) ||
      role(session.role) !== "ADMIN" || session.adminUid !== uid) {
    return blocked("INVALID_ADMIN_SESSION");
  }

  // Le compte de connexion est une collection protégée côté clients.
  // Il est indexé par login/email et non par uid : retrouver ce compte par
  // son adminUid, au lieu de supposer adminAccounts/{uid}.
  const accounts = await db.collection("adminAccounts")
      .where("adminUid", "==", uid).limit(10).get();
  if (accounts.docs.length === 10) return blocked("AMBIGUOUS_ADMIN_ACCOUNT");
  const active = accounts.docs.filter((doc) => {
    const data = doc.data() || {};
    return data.accountStatus === "ACTIVE" &&
        role(data.role) === "ADMIN" &&
        data.adminUid === uid && data.territoireId === territory;
  });
  if (active.length !== 1) return blocked("ADMIN_ACCOUNT_NOT_ACTIVE");
  const account = active[0].data() || {};

  // Le DV actuel exige adminUid===requestId. Refuser les variantes
  // historiques non compatibles plutôt que deviner une association.
  const requestId = string(account.requestId) || uid;
  if (requestId !== uid) return blocked("REQUEST_MAPPING_NOT_SUPPORTED");

  const [adminSnap, requestSnap, subscriptionSnap] = await Promise.all([
    db.collection("admins").doc(uid).get(),
    db.collection("adminRequests").doc(requestId).get(),
    db.collection("subscriptions").doc(uid).get(),
  ]);
  const admin = read(adminSnap);
  const request = read(requestSnap);
  const subscription = read(subscriptionSnap);
  const requestTerritory = request && request.territoire || {};
  const requestTerritoryId = string(requestTerritory.territoireId ||
      (request && request.territoireId));
  if (!admin || !request || !subscription ||
      admin.uid !== uid || request.uid !== uid ||
      request.status !== "approved" ||
      role(admin.role) !== "ADMIN" ||
      admin.accessStatus !== "approved" ||
      admin.territoireId !== territory ||
      requestTerritoryId !== territory ||
      !/^SPHOT-ADM-(?:[A-Z]{3}-)?\d{4}-\d{6}$/.test(
          string(request.requestNumber))) {
    return blocked("ADMIN_DOSSIER_INCOMPLETE_OR_INCONSISTENT");
  }

  // La liste est une SÉLECTION déclarative. Chaque poste est relu depuis
  // la vraie sous-collection de ce territoire, jamais depuis le résumé
  // sélectionné ni depuis un simple compteur modifiable dans subscription.
  const chosen = subscription.selectedRescueStationIds;
  if (!Array.isArray(chosen) || chosen.length === 0 ||
      chosen.length > 10000 || chosen.some((id) => !safeId(id)) ||
      new Set(chosen).size !== chosen.length) {
    return blocked("STATION_SELECTION_INVALID");
  }
  const spotRefs = chosen.map((id) => db.collection("territoires")
      .doc(territory).collection("spots").doc(id));
  const spotSnapshots = await Promise.all(spotRefs.map((ref) => ref.get()));
  const stations = [];
  for (let i = 0; i < chosen.length; i++) {
    const spot = read(spotSnapshots[i]);
    if (!spot || !isRescueStation(spot) || !spotName(spot) ||
        (string(spot.territoireId) && spot.territoireId !== territory)) {
      return blocked("STATION_NOT_FOUND_IN_ADMIN_TERRITORY");
    }
    stations.push({
      spotDocumentId: chosen[i],
      idSphot: string(spot.idSphot),
      name: spotName(spot),
    });
  }

  // Recalcul serveur depuis commercialPricingMarkets/FR_ADMIN.
  // Le prix et le nombre saisis dans subscriptions ne font pas autorité.
  let quote;
  try {
    const snap = await db.collection("commercialPricingMarkets")
        .doc("FR_ADMIN").get();
    quote = adminQuote(publishedState(snap, "ADMIN"), stations.length);
  } catch (_) {
    return blocked("PUBLISHED_PRICING_UNAVAILABLE");
  }

  const structure = request.structure || {};
  const profile = request.profile || {};
  const otherPayer = subscription.billingPayerRelation === "other";
  const billing = {
    legalName: otherPayer ?
      string(subscription.billingOrganisation) :
      nonEmpty(subscription.billingOrganisation, structure.nom),
    country: country(otherPayer ? subscription.billingCountry :
      nonEmpty(subscription.billingCountry, requestTerritory.pays)),
    siret: otherPayer ? string(subscription.billingSiret) :
      nonEmpty(subscription.billingSiret, structure.siret),
    officialId: string(subscription.billingLegalId),
    address: otherPayer ? string(subscription.billingAddress) :
      nonEmpty(subscription.billingAddress, requestTerritory.adresse),
    postalCode: otherPayer ? string(subscription.billingPostalCode) :
      nonEmpty(subscription.billingPostalCode, requestTerritory.codePostal),
    city: otherPayer ? string(subscription.billingCity) :
      nonEmpty(subscription.billingCity, requestTerritory.ville),
    billingEmail: otherPayer ? string(subscription.billingContactEmail) :
      nonEmpty(subscription.billingContactEmail, profile.email),
    isDifferentFromManager: otherPayer,
    // Purement déclaratif ; aucune preuve de contrôle légal.
    legalIdentityVerified: false,
    thirdPartyBillingAuthorized: false,
  };
  const complete = Boolean(billing.legalName && billing.country &&
      billing.address && billing.postalCode && billing.city &&
      /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(billing.billingEmail) &&
      (billing.country === "FR" ? /^\d{14}$/.test(billing.siret) :
        Boolean(billing.officialId)));

  return Object.freeze({
    status: "draft_preview",
    adminUid: uid,
    territoireId: territory,
    requestId,
    administrativeReference: request.requestNumber,
    stations,
    buyer: billing,
    buyerFieldsComplete: complete,
    publishedQuote: quote,
    source: "firestore_server_read",
    legalIdentityVerified: false,
    fiscalityVerified: false,
    issuanceAuthorized: false,
    // Sans émetteur immatriculé ni décision fiscale : ni TVA ni TTC ici.
    taxAmount: null,
    amountInclTax: null,
  });
}

module.exports = {loadRealAdminQuoteDraft};
