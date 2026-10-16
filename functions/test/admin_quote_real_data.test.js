/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {loadRealAdminQuoteDraft} =
    require("../admin_quote_real_data");

const UID = "admin-1";
const TERR = "terr-1";
const REF = "SPHOT-ADM-FRA-2026-000001";

function fixture() {
  const values = new Map();
  const reads = [];
  const quotes = new Map();
  const docs = (path, id) => ({
    id,
    data: () => ({...values.get(path)}),
  });
  const snap = (path) => ({
    exists: values.has(path),
    data: () => ({...values.get(path)}),
  });
  const makeCollection = (prefix) => ({
    doc(id) {
      const path = prefix + "/" + id;
      return {
        id, path,
        get: async () => {
          reads.push(path);
          return snap(path);
        },
        collection(sub) {
          return makeCollection(path + "/" + sub);
        },
      };
    },
    where(field, op, value) {
      if (prefix !== "adminAccounts" || field !== "adminUid" ||
          op !== "==") throw new Error("Unexpected query");
      return {
        limit(n) {
          assert.equal(n, 10);
          return {
            async get() {
              reads.push(prefix + "?adminUid=" + value);
              return {docs: [...values.keys()].filter(
                  (p) => p.startsWith(prefix + "/") &&
                  values.get(p).adminUid === value).map(
                  (p) => docs(p, p.split("/").pop()))};
            },
          };
        },
      };
    },
  });
  const db = {collection: makeCollection};
  const session = {
    uid: UID, adminUid: UID, role: "ADMIN", territoireId: TERR,
  };
  const auth = {
    verifyIdToken: async (token, revoked) => {
      assert.equal(revoked, true);
      if (token !== "FAKE_TOKEN") throw new Error("Invalid");
      return session;
    },
  };
  const put = (path, value) => values.set(path, value);
  put("adminAccounts/pro@example.invalid", {
    accountStatus: "ACTIVE", role: "ADMIN",
    adminUid: UID, requestId: UID, territoireId: TERR,
  });
  put("admins/" + UID, {
    uid: UID, role: "admin", accessStatus: "approved",
    territoireId: TERR,
  });
  put("adminRequests/" + UID, {
    uid: UID, status: "approved",
    requestNumber: REF,
    territoire: {
      territoireId: TERR, pays: "France", ville: "Commune Fictive",
      adresse: "2 rue Test", codePostal: "75002",
    },
    structure: {nom: "Commune Fictive", siret: "12345678901234"},
    profile: {email: "pro@example.invalid"},
  });
  put("subscriptions/" + UID, {
    adminUid: UID,
    billingPayerRelation: "manager",
    selectedRescueStationIds: ["spot1", "spot2"],
    annualAmountExclTax: 1, // Une valeur manipulée ne fait PAS autorité.
    numberOfRescueStations: 9999,
  });
  put("territoires/" + TERR + "/spots/spot1", {
    typeSphot: "POSTE DE SECOURS", idSphot: "TEST 01",
    nomSphot: "Plage Fictive A", territoireId: TERR,
  });
  put("territoires/" + TERR + "/spots/spot2", {
    isPosteSecours: true, idSphot: "TEST 02",
    nomSecours: "Plage Fictive B", territoireId: TERR,
  });
  put("commercialPricingMarkets/FR_ADMIN", {
    type: "ADMIN", country: "FR", currency: "EUR",
    publishedVersion: 3, publishedPrices: [499, 399, 299, 199],
  });
  const call = (idToken = "FAKE_TOKEN") => loadRealAdminQuoteDraft({
    db, auth, idToken,
  });
  return {values, reads, quotes, session, auth, db, put, call};
}

test("Dossier réel simulé : lecture des collections et tarif recalculé", async () => {
  const f = fixture();
  const result = await f.call();
  assert.equal(result.status, "draft_preview");
  assert.equal(result.adminUid, UID);
  assert.equal(result.territoireId, TERR);
  assert.equal(result.administrativeReference, REF);
  assert.equal(result.stations.length, 2);
  assert.equal(result.buyer.legalName, "Commune Fictive");
  assert.equal(result.buyer.country, "FR");
  assert.equal(result.buyerFieldsComplete, true);
  assert.equal(result.publishedQuote.pricingReference, "FR_ADMIN-V3");
  assert.equal(result.publishedQuote.amountExclTax, 898);
  assert.equal(result.legalIdentityVerified, false);
  assert.equal(result.fiscalityVerified, false);
  assert.equal(result.issuanceAuthorized, false);
  assert.equal(result.taxAmount, null);
  assert.equal(result.amountInclTax, null);
  assert.ok(f.reads.includes("commercialPricingMarkets/FR_ADMIN"));
  assert.ok(f.reads.includes("territoires/" + TERR + "/spots/spot1"));
});

test("Une session Firebase révoquée ou invalide est refusée", async () => {
  const f = fixture();
  assert.deepEqual((await f.call("INVALID")).reasonCodes,
      ["INVALID_ADMIN_SESSION"]);
  assert.equal(f.reads.length, 0);
});

test("Un rôle publicitaire ne peut lire les coordonnées Admin", async () => {
  const f = fixture();
  f.session.role = "ANNONCEUR";
  assert.deepEqual((await f.call()).reasonCodes,
      ["INVALID_ADMIN_SESSION"]);
  assert.equal(f.reads.length, 0);
});

test("Compte Admin inactif : refus avant les dossiers", async () => {
  const f = fixture();
  f.values.get("adminAccounts/pro@example.invalid").accountStatus =
      "SUSPENDED";
  assert.deepEqual((await f.call()).reasonCodes,
      ["ADMIN_ACCOUNT_NOT_ACTIVE"]);
  assert.equal(f.reads.some((p) => p.startsWith("subscriptions/")), false);
});

test("Plusieurs comptes actifs pour le même uid : refus ambigu", async () => {
  const f = fixture();
  f.put("adminAccounts/autre@example.invalid", {
    accountStatus: "ACTIVE", role: "ADMIN",
    adminUid: UID, territoireId: TERR,
  });
  assert.deepEqual((await f.call()).reasonCodes,
      ["ADMIN_ACCOUNT_NOT_ACTIVE"]);
});

test("Territoire déclaré différent du token : refus", async () => {
  const f = fixture();
  f.values.get("admins/" + UID).territoireId = "autre-territoire";
  assert.deepEqual((await f.call()).reasonCodes,
      ["ADMIN_DOSSIER_INCOMPLETE_OR_INCONSISTENT"]);
});

test("Un dossier jamais approuvé ne peut être utilisé", async () => {
  const f = fixture();
  f.values.get("adminRequests/" + UID).status = "pending";
  assert.deepEqual((await f.call()).reasonCodes,
      ["ADMIN_DOSSIER_INCOMPLETE_OR_INCONSISTENT"]);
});

test("Un dossier historique dont requestId diffère du uid est bloqué", async () => {
  const f = fixture();
  f.values.get("adminAccounts/pro@example.invalid").requestId =
      "different";
  assert.deepEqual((await f.call()).reasonCodes,
      ["REQUEST_MAPPING_NOT_SUPPORTED"]);
});

test("Un poste absent ou hors du territoire est refusé", async () => {
  const f = fixture();
  f.values.get("territoires/" + TERR + "/spots/spot2")
      .territoireId = "other";
  assert.deepEqual((await f.call()).reasonCodes,
      ["STATION_NOT_FOUND_IN_ADMIN_TERRITORY"]);
  f.put("territoires/" + TERR + "/spots/spot2", {
    typeSphot: "PLAGE", nomSphot: "Sans poste",
  });
  assert.deepEqual((await f.call()).reasonCodes,
      ["STATION_NOT_FOUND_IN_ADMIN_TERRITORY"]);
});

test("La sélection de postes ne peut comporter des doublons", async () => {
  const f = fixture();
  f.values.get("subscriptions/" + UID).selectedRescueStationIds =
      ["spot1", "spot1"];
  assert.deepEqual((await f.call()).reasonCodes,
      ["STATION_SELECTION_INVALID"]);
});

test("Le prix client falsifié ne modifie pas le tarif publié", async () => {
  const f = fixture();
  f.values.get("subscriptions/" + UID).annualAmountExclTax = 999999;
  f.values.get("subscriptions/" + UID).numberOfRescueStations = 15;
  assert.equal((await f.call()).publishedQuote.amountExclTax, 898);
});

test("Payeur distinct : ne jamais compléter les champs depuis la mairie", async () => {
  const f = fixture();
  f.values.get("subscriptions/" + UID).billingPayerRelation = "other";
  const result = await f.call();
  assert.equal(result.status, "draft_preview");
  assert.equal(result.buyer.legalName, "");
  assert.equal(result.buyer.siret, "");
  assert.equal(result.buyerFieldsComplete, false);
  assert.equal(result.buyer.isDifferentFromManager, true);
  assert.equal(result.buyer.thirdPartyBillingAuthorized, false);
});

test("Si grille non publiée, impossible de chiffrer le brouillon", async () => {
  const f = fixture();
  f.values.get("commercialPricingMarkets/FR_ADMIN")
      .publishedVersion = 0;
  assert.deepEqual((await f.call()).reasonCodes,
      ["PUBLISHED_PRICING_UNAVAILABLE"]);
});

test("Le module ne dispose d'aucune opération d'écriture", async () => {
  const f = fixture();
  let changed = false;
  f.db.collection = ((original) => (name) => {
    const instance = original(name);
    instance.set = () => {
      changed = true;
      throw new Error("write");
    };
    return instance;
  })(f.db.collection);
  await f.call();
  assert.equal(changed, false);
});
