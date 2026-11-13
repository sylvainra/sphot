"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {validateMaterialVerification} =
    require("../sauveteur_material_verification");

const source = fs.readFileSync(
    path.join(__dirname, "../index.js"), "utf8");
const recordRoute = source.split(
    "exports.recordSauveteurMaterialVerification =")[1]
    .split("exports.addSauveteurMainCouranteEntry =")[0];
const freeTextRoute = source.split(
    "exports.addSauveteurMainCouranteEntry =")[1]
    .split("exports.")[0];

test("les quatre catégories sont acceptées et identifiées", () => {
  const labels = {
    medical: "Secours",
    phonie: "Phonie / communications",
    roulant: "Matériel roulant",
    flottant: "Matériel flottant",
  };
  for (const [category, label] of Object.entries(labels)) {
    const result = validateMaterialVerification({
      verificationCategory: category,
      description: `Catégorie : ${label}\nContrôle : OK`,
      type: "Intervention", visibility: "restricted",
      createdBy: {login: "usurpation"},
    });
    assert.deepEqual(result, {
      category, description: `Catégorie : ${label}\nContrôle : OK`,
    });
  }
});

test("les catégories inexistantes ou les saisies vides sont rejetées", () => {
  const valid = "Catégorie : Secours\nContrôle : OK";
  assert.equal(validateMaterialVerification(null), null);
  assert.equal(validateMaterialVerification({}), null);
  assert.equal(validateMaterialVerification({
    verificationCategory: "intervention", description: valid,
  }), null);
  assert.equal(validateMaterialVerification({
    verificationCategory: "medical", description: "",
  }), null);
  assert.equal(validateMaterialVerification({
    verificationCategory: "medical",
    description: "Catégorie : Phonie / communications\nContrôle : OK",
  }), null);
  assert.equal(validateMaterialVerification({
    verificationCategory: "medical",
    description: "Catégorie : Secours",
  }), null);
});

test("les textes excessifs sont rejetés", () => {
  assert.equal(validateMaterialVerification({
    verificationCategory: "medical",
    description: "Catégorie : Secours\n" + "A".repeat(8100),
  }), null);
});

test("la nouvelle fonction contrôle session, accord et poste SPHOT ON", () => {
  assert.match(recordRoute, /resolveSauveteurSession/);
  assert.match(recordRoute, /legalAcceptanceCurrent/);
  assert.match(recordRoute, /context\.sphotMode !== "ON"/);
  assert.match(recordRoute, /context\.realtimeSpotIds\.includes\(spotId\)/);
  assert.match(recordRoute, /validateMaterialVerification\(body\)/);
  assert.doesNotMatch(recordRoute, /canManageRestrictedOperationalData/);
});

test("type, auteur et horodatage sont imposés par le serveur", () => {
  assert.match(recordRoute, /type: "Vérifications"/);
  assert.match(recordRoute, /verificationCategory: verification\.category/);
  assert.match(recordRoute, /source: "material_verification"/);
  assert.match(recordRoute, /serverTimestamp\(\)/);
  assert.match(recordRoute, /login: session\.login/);
  assert.match(recordRoute, /\.collection\("mainCourante"\)/);
  assert.match(recordRoute, /\.doc\(\)/);
});

test("la rédaction libre reste réservée au chef et à l'adjoint", () => {
  assert.match(freeTextRoute,
      /if \(!context\.canManageRestrictedOperationalData\)/);
});

test("modification et suppression : droits et audit", () => {
  const edit = source.split(
      "exports.updateSauveteurMainCouranteEntry =")[1]
      .split("exports.deleteSauveteurMainCouranteEntry =")[0];
  const removal = source.split(
      "exports.deleteSauveteurMainCouranteEntry =")[1]
      .split("exports.")[0];
  for (const route of [edit, removal]) {
    assert.match(route, /canManageRestrictedOperationalData/);
    assert.match(route, /mainCouranteAuditLogs/);
  }
});

test("les changements de drapeau sont inscrits avec l'auteur", () => {
  const live = source.split("exports.updateSauveteurLiveState =")[1]
      .split("exports.")[0];
  assert.match(live, /flagJournalLines\.length > 0/);
  assert.match(live, /source: "automatic_flag_event"/);
  assert.match(live, /login: session\.login/);
  assert.match(live, /serverTimestamp\(\)/);
});

// Exécute le véritable gestionnaire Cloud Functions avec Firebase simulé.
const vm = require("node:vm");

/**
 * Prépare un appel HTTP au endpoint exact de functions/index.js.
 * @param {Object} options Simulation du compte et du poste.
 * @return {Object} Méthode invoke et écritures capturées.
 */
function verificationEndpointFixture(options = {}) {
  const writes = [];
  const context = {
    sphotMode: options.mode || "ON",
    realtimeSpotIds: options.assigned === false ? [] : ["poste-test"],
    territoireId: "territoire-test",
    sauveteurId: "sauveteur-test",
    userRole: "SAUVETEUR",
    canManageRestrictedOperationalData: options.supervisor === true,
  };
  const firestore = () => ({
    collection: (name) => {
      assert.equal(name, "territoires");
      return {doc: () => ({
        collection: () => ({doc: () => ({
          collection: () => ({doc: () => ({
            id: "entry-" + (writes.length + 1),
            set: async (data) => writes.push(data),
          })}),
        })}),
      })};
    },
  });
  firestore.FieldValue = {serverTimestamp: () => "SERVER_TIMESTAMP"};
  const sandbox = {
    exports: {},
    onRequest: (_options, handler) => handler,
    admin: {firestore},
    validateMaterialVerification,
    resolveSauveteurSession: async () => options.authenticated === false ?
      null : {
        login: "sauveteur-test",
        legalAcceptanceCurrent: options.accepted !== false,
        context,
      },
    console,
  };
  vm.runInNewContext(
      "exports.recordSauveteurMaterialVerification =" + recordRoute,
      sandbox);

  return {
    writes,
    invoke: async (overrides = {}) => {
      const response = {
        statusCode: 200,
        result: null,
        set() {
          return this;
        },
        status(code) {
          this.statusCode = code;
          return this;
        },
        json(value) {
          this.result = value;
          return this;
        },
        send() {
          return this;
        },
      };
      const body = {
        sauveteurSessionToken: "session-test",
        spotId: "poste-test",
        verificationCategory: "medical",
        description: "Catégorie : Secours\nContrôle : OK",
        ...overrides,
      };
      await sandbox.exports.recordSauveteurMaterialVerification(
          {method: "POST", body}, response);
      return response;
    },
  };
}

test("un sauveteur simple peut enregistrer plusieurs contrôles", async () => {
  const harness = verificationEndpointFixture({supervisor: false});
  const first = await harness.invoke({createdBy: {login: "faux"}});
  const second = await harness.invoke();
  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200);
  assert.equal(harness.writes.length, 2);
  assert.equal(harness.writes[0].createdBy.login, "sauveteur-test");
  assert.equal(harness.writes[0].occurredAt, "SERVER_TIMESTAMP");
  assert.equal(harness.writes[0].verificationCategory, "medical");
  assert.equal(harness.writes[0].type, "Vérifications");
});

test("session absente, accord manquant et poste interdit refusés", async () => {
  const cases = [
    [{authenticated: false}, 401],
    [{accepted: false}, 403],
    [{mode: "OFF"}, 403],
    [{assigned: false}, 403],
  ];
  for (const [options, expectedStatus] of cases) {
    const harness = verificationEndpointFixture(options);
    const response = await harness.invoke();
    assert.equal(response.statusCode, expectedStatus);
    assert.equal(harness.writes.length, 0);
  }
});

test("le endpoint refuse une fausse catégorie matériel", async () => {
  const harness = verificationEndpointFixture();
  const response = await harness.invoke({
    verificationCategory: "intervention",
  });
  assert.equal(response.statusCode, 400);
  assert.equal(harness.writes.length, 0);
});
