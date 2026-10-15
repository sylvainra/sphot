/* eslint-disable max-len, require-jsdoc, valid-jsdoc, object-curly-spacing, indent */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {assignAuthorizedAdminQuoteNumber} =
    require("../admin_quote_numbering");

const QUOTE_ID = "quote-1";
const REQUEST_ID = "admin-1";
const REF = "SPHOT-ADM-2026-000001";
const NUMBER = "DV-2026-000001-001";

function fakeEnvironment() {
  const values = new Map();
  const counters = {transactions: 0, writes: 0};
  function ref(path) {
    const parts = path.split("/");
    return {path, id: parts[parts.length - 1]};
  }
  function snapshot(reference) {
    const value = values.get(reference.path);
    return {exists: value !== undefined, data: () => value,
      ref: reference};
  }
  function transaction() {
    const pending = [];
    let wrote = false;
    return {
      get: async (r) => {
        if (wrote) throw new Error("Lecture après écriture");
        return snapshot(r);
      },
      set: (r, value, options) => {
        wrote = true;
        pending.push(["set", r.path, value, options]);
      },
      update: (r, value) => {
        wrote = true;
        pending.push(["update", r.path, value]);
      },
      commit: () => {
        for (const [kind, path, value] of pending) {
          const old = values.get(path) || {};
          values.set(path, kind === "set" || kind === "update" ?
            {...old, ...value} : value);
          counters.writes++;
        }
      },
    };
  }
  const db = {
    collection: (collection) => ({
      doc: (id) => ref(collection + "/" + id),
    }),
    runTransaction: async (callback) => {
      counters.transactions++;
      const tx = transaction();
      const result = await callback(tx);
      tx.commit();
      return result;
    },
  };
  const event = {data: {after: {exists: true,
    ref: ref("quotes/" + QUOTE_ID)}}};
  const call = () => assignAuthorizedAdminQuoteNumber({
    db, event, serverTimestamp: () => "TEST_TIMESTAMP",
  });
  values.set("quotes/" + QUOTE_ID, {
    quoteId: QUOTE_ID, adminUid: REQUEST_ID,
    requestId: REQUEST_ID, administrativeReference: REF,
    issuedOn: "2026-10-15", subscriptionYear: 2026,
    validUntil: "2026-11-13",
    status: "authorized_pending_number",
  });
  values.set("adminRequests/" + REQUEST_ID, {
    uid: REQUEST_ID, requestNumber: REF,
  });
  const approval = () => ({
    type: "official_admin_quote", status: "approved_for_numbering",
    quoteId: QUOTE_ID, adminUid: REQUEST_ID,
    requestId: REQUEST_ID, administrativeReference: REF,
    issuedOn: "2026-10-15", subscriptionYear: 2026,
    validUntil: "2026-11-13",
    issuerLegallyVerified: true, fiscalityVerified: true,
    publishedPricingVerified: true, buyerVerified: true,
    stationsVerified: true, adminRightsVerified: true,
    thirdPartyBillingVerified: true,
  });
  return {values, counters, event, db, call, approval,
    authorize: () => values.set("quoteIssueAuthorizations/" + QUOTE_ID,
        approval())};
}

test("Brouillon : aucun numéro ni compteur n'est créé", async () => {
  const t = fakeEnvironment();
  t.values.get("quotes/" + QUOTE_ID).status = "draft";
  t.authorize();
  assert.equal(await t.call(), false);
  assert.equal(t.values.has("counters/quotes_2026_000001"), false);
});

test("Un statut prétendument prêt sans autorisation serveur ne suffit pas", async () => {
  const t = fakeEnvironment();
  assert.equal(await t.call(), false);
  assert.equal(t.counters.writes, 0);
});

test("Une autorisation qui n'a pas vérifié l'émetteur est refusée", async () => {
  const t = fakeEnvironment();
  t.authorize();
  t.values.get("quoteIssueAuthorizations/" + QUOTE_ID)
      .issuerLegallyVerified = false;
  assert.equal(await t.call(), false);
  assert.equal(t.counters.writes, 0);
});

test("La fiscalité et les droits Admin doivent être vérifiés", async () => {
  const t = fakeEnvironment();
  t.authorize();
  const auth = t.values.get("quoteIssueAuthorizations/" + QUOTE_ID);
  auth.fiscalityVerified = false;
  auth.adminRightsVerified = false;
  assert.equal(await t.call(), false);
  assert.equal(t.counters.writes, 0);
});

test("Une autorisation d'un autre Admin ou devis est rejetée", async () => {
  const t = fakeEnvironment();
  t.authorize();
  const auth = t.values.get("quoteIssueAuthorizations/" + QUOTE_ID);
  auth.adminUid = "admin-2";
  assert.equal(await t.call(), false);
  assert.equal(t.counters.writes, 0);
});

test("Le rattachement à la demande Admin est obligatoire", async () => {
  const t = fakeEnvironment();
  t.authorize();
  t.values.get("adminRequests/" + REQUEST_ID).requestNumber =
      "SPHOT-ADM-2026-999999";
  assert.equal(await t.call(), false);
  assert.equal(t.counters.writes, 0);
});

test("Date et validité incohérentes : aucune numérotation", async () => {
  const t = fakeEnvironment();
  t.authorize();
  t.values.get("quotes/" + QUOTE_ID).validUntil = "2027-10-15";
  assert.equal(await t.call(), false);
  assert.equal(t.counters.writes, 0);
});

test("Une autorisation approuvée réserve un DV en transaction", async () => {
  const t = fakeEnvironment();
  t.authorize();
  assert.equal(await t.call(), true);
  assert.equal(t.values.get("quotes/" + QUOTE_ID).quoteNumber, NUMBER);
  assert.equal(t.values.get("quotes/" + QUOTE_ID).status,
      "numbered_pending_archive");
  assert.equal(t.values.get("counters/quotes_2026_000001").lastNumber, 1);
  assert.equal(t.values.get("quoteIssueAuthorizations/" + QUOTE_ID)
      .status, "numbered");
});

test("Deux exécutions ne consomment pas deux numéros", async () => {
  const t = fakeEnvironment();
  t.authorize();
  assert.equal(await t.call(), true);
  const firstWrites = t.counters.writes;
  assert.equal(await t.call(), false);
  assert.equal(t.counters.writes, firstWrites);
  assert.equal(t.values.get("counters/quotes_2026_000001").lastNumber, 1);
});

test("Une autorisation déjà consommée ne peut pas resservir", async () => {
  const t = fakeEnvironment();
  t.authorize();
  t.values.get("quoteIssueAuthorizations/" + QUOTE_ID)
      .status = "numbered";
  assert.equal(await t.call(), false);
  assert.equal(t.counters.writes, 0);
});

test("Un compteur corrompu bloque la numérotation", async () => {
  const t = fakeEnvironment();
  t.authorize();
  t.values.set("counters/quotes_2026_000001", {lastNumber: -2});
  await assert.rejects(t.call(), /Compteur de devis invalide/);
  assert.equal(t.values.get("quotes/" + QUOTE_ID).quoteNumber, undefined);
});

test("Un numéro préexistant n'est jamais remplacé", async () => {
  const t = fakeEnvironment();
  t.authorize();
  t.values.get("quotes/" + QUOTE_ID).quoteNumber = "DV-2026-000001-099";
  assert.equal(await t.call(), false);
  assert.equal(t.counters.writes, 0);
});
