/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {adminQuote, publishedState} = require("./commercial_quote_pricing");

const str = (value) => typeof value === "string" ? value.trim() : "";
const safeId = (value) => /^[A-Za-z0-9_-]{1,220}$/.test(str(value));
const read = (snap) => snap && snap.exists ? snap.data() || {} : {};
const upper = (value) => str(value).toUpperCase();
const country = (value) => ["FR", "FRA", "FRANCE"].includes(upper(value)) ?
  "FR" : str(value);
const first = (...values) => values.map(str).find(Boolean) || "";

function denied() {
  const error = new Error("Accès au devis consultable refusé.");
  error.code = "ADMIN_QUOTE_CONSULTATION_DENIED";
  return error;
}

// Lecture isolée, en seule consultation. Ne renvoie pas au client les
// données personnelles : elles sont directement transmises au moteur PDF.
// Le propriétaire doit être identifié par son TOKEN, pas un uid client.
// "admins", "subscriptions" et "settings" ne sont pas une preuve
// juridique/fiscale ; elles ne peuvent servir qu'à cette consultation.
async function loadAdminQuoteConsultationContext({auth, db, idToken} = {}) {
  if (!auth || typeof auth.verifyIdToken !== "function" ||
      !db || typeof db.collection !== "function" || !str(idToken)) {
    throw denied();
  }
  let session;
  try {
    session = await auth.verifyIdToken(idToken, true);
  } catch (_) {
    throw denied();
  }
  const uid = str(session?.uid);
  const territory = str(session?.territoireId);
  if (!safeId(uid) || !safeId(territory) ||
      session.adminUid !== uid || upper(session.role) !== "ADMIN") {
    throw denied();
  }
  const accounts = await db.collection("adminAccounts")
      .where("adminUid", "==", uid).limit(10).get();
  if (!accounts || !Array.isArray(accounts.docs) ||
      accounts.docs.length >= 10) throw denied();
  const matches = accounts.docs.filter((item) => {
    const account = item.data() || {};
    return account.adminUid === uid &&
        account.territoireId === territory &&
        upper(account.role) === "ADMIN" &&
        account.accountStatus === "ACTIVE";
  });
  if (matches.length !== 1) throw denied();
  const account = matches[0].data();
  const requestId = first(account.requestId, uid);
  if (!safeId(requestId)) throw denied();

  const [adminSnap, requestSnap, subscriptionSnap, issuerSnap] =
      await Promise.all([
        db.collection("admins").doc(uid).get(),
        db.collection("adminRequests").doc(requestId).get(),
        db.collection("subscriptions").doc(uid).get(),
        db.collection("settings").doc("sphotLegalIdentity").get(),
      ]);
  const admin = read(adminSnap);
  const request = read(requestSnap);
  const subscription = read(subscriptionSnap);
  // Autorisation de consultation fondée sur le compte serveur actif
  // et l'accès Admin, pas sur l'état des coordonnées de facturation.
  if (upper(admin.role) !== "ADMIN" ||
      admin.accessStatus !== "approved" ||
      admin.territoireId !== territory ||
      (request.uid && request.uid !== uid) ||
      (request.territoire?.territoireId &&
       request.territoire.territoireId !== territory)) {
    throw denied();
  }

  const rawSelection = subscription.selectedRescueStationIds;
  const chosen = Array.isArray(rawSelection) ?
    rawSelection.filter((id) => safeId(id)) : [];
  // Selection suspecte : aperçu sans prix, et sans accès à un autre territoire.
  const safeSelection = chosen.length <= 100 &&
      rawSelection instanceof Array && chosen.length === rawSelection.length &&
      new Set(chosen).size === chosen.length;
  const stationIds = safeSelection ? chosen : [];
  const stations = [];
  let allRescueStationsVerified = stationIds.length > 0;
  if (stationIds.length > 0) {
    const snapshots = await Promise.all(stationIds.map((id) =>
      db.collection("territoires").doc(territory)
          .collection("spots").doc(id).get()));
    for (let i = 0; i < stationIds.length; i++) {
      const spot = read(snapshots[i]);
      const rescued = spot.isPosteSecours === true ||
        upper(spot.typeSphot).includes("POSTE DE SECOURS");
      const name = first(spot.nomSphot, spot.nomSecours,
          spot.name, spot.nom, spot.title);
      const sameTerritory = !str(spot.territoireId) ||
          spot.territoireId === territory;
      if (!snapshots[i].exists || !rescued || !name || !sameTerritory) {
        allRescueStationsVerified = false;
      }
      stations.push({
        idSphot: sameTerritory ? str(spot.idSphot) : "",
        name: sameTerritory && rescued && name ?
          name : "Poste à identifier : " + stationIds[i],
      });
    }
  }

  let pricing = null;
  if (allRescueStationsVerified) {
    try {
      const market = await db.collection("commercialPricingMarkets")
          .doc("FR_ADMIN").get();
      pricing = adminQuote(publishedState(market, "ADMIN"),
          stationIds.length);
      pricing.fromServerPublishedCatalog = true;
    } catch (_) {
      // L'absence de tarif publié n'interdit jamais le document consultable.
    }
  }

  const territoire = request.territoire || {};
  const structure = request.structure || {};
  const profile = request.profile || {};
  const other = subscription.billingPayerRelation === "other";
  const buyer = {
    legalName: other ?
      str(subscription.billingOrganisation) :
      first(subscription.billingOrganisation, structure.nom),
    country: country(other ? subscription.billingCountry :
      first(subscription.billingCountry, territoire.pays)),
    siret: other ? str(subscription.billingSiret) :
      first(subscription.billingSiret, structure.siret),
    officialId: str(subscription.billingLegalId),
    address: other ? str(subscription.billingAddress) :
      first(subscription.billingAddress, territoire.adresse),
    postalCode: other ? str(subscription.billingPostalCode) :
      first(subscription.billingPostalCode, territoire.codePostal),
    city: other ? str(subscription.billingCity) :
      first(subscription.billingCity, territoire.ville),
    billingContactName: str(subscription.billingContactName),
    billingEmail: other ? str(subscription.billingContactEmail) :
      first(subscription.billingContactEmail, profile.email),
  };
  const rawIssuer = read(issuerSnap);
  const issuer = {
    legalName: first(rawIssuer.legalName, "SPHOT"),
    country: country(rawIssuer.country),
    siret: str(rawIssuer.siret),
    officialId: str(rawIssuer.officialId),
    address: str(rawIssuer.address),
    postalCode: str(rawIssuer.postalCode),
    city: str(rawIssuer.city),
    email: str(rawIssuer.email),
    vatNumber: str(rawIssuer.vatNumber),
  };

  return {
    administrativeReference: first(request.requestNumber,
        subscription.administrativeReference),
    issuer, buyer, stations,
    publishedQuote: pricing,
    taxDecision: null,
    // Aucune permission d'émission ne peut être déduite de cet objet.
    issuanceAuthorized: false,
  };
}

module.exports = {loadAdminQuoteConsultationContext};
