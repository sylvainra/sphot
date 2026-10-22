"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildCorrectionFieldPatch, FIELD_SCOPES} =
    require("../advertiser_correction_fields");
const {buildDecisionUpdate} = require("../advertiser_review_decision");

const fv = {
  serverTimestamp: () => "SERVER_TIME",
  arrayUnion: (...values) => ({arrayUnion: values}),
};
const timestamp = {now: () => "NOW"};
const requestId = "advertiser123";

function correction(fields) {
  return {
    status: "changes_requested",
    contactFirstName: "Camille",
    contactLastName: "MARTIN",
    establishment: {legalName: "EXISTING COMPANY", city: "NANTES",
      activityTypes: ["Sports nautiques"]},
    correctionRequest: {status: "changes_requested", fields},
  };
}

test("une correction modifie uniquement les champs sélectionnés", () => {
  const current = correction(["identity.contactPhone", "establishment.city"]);
  const patch = buildCorrectionFieldPatch(current, {
    "identity.contactPhone": "0612345678",
    "establishment.city": "BORDEAUX",
  }, fv, requestId);
  assert.equal(patch.contactPhone, "0612345678");
  assert.equal(patch["establishment.city"], "BORDEAUX");
  assert.equal(patch["establishment.legalName"], undefined);
  assert.equal(patch.status, undefined);
  assert.equal(patch.review, undefined);
});

test("refuse un champ non sélectionné et les statuts", () => {
  const current = correction(["identity.contactPhone"]);
  assert.throws(() => buildCorrectionFieldPatch(current, {
    "identity.contactLastName": "DUPONT",
  }, fv, requestId), /non autorisée/);
  assert.throws(() => buildCorrectionFieldPatch(current, {
    status: "approved",
  }, fv, requestId), /non autorisée/);
});

test("verrouille les corrections après retransmission", () => {
  const current = correction(["identity.contactPhone"]);
  current.status = "pending";
  assert.throws(() => buildCorrectionFieldPatch(current, {
    "identity.contactPhone": "0612345678",
  }, fv, requestId), /Aucune correction/);
});

test("conserve les autres activités et la précision Autre", () => {
  const current = correction(["establishment.activityTypes"]);
  const patch = buildCorrectionFieldPatch(current, {
    "establishment.activityTypes": {
      types: ["Sports nautiques", "Autre"],
      other: "Location planches de surf",
    },
  }, fv, requestId);
  assert.deepEqual(patch["establishment.activityTypes"],
      ["Sports nautiques", "Autre"]);
  assert.equal(patch["establishment.activityTypeOther"],
      "Location planches de surf");
  assert.equal(patch["establishment.activityType"], "Sports nautiques");
});

test("refuse Autre sans précision et choix d'activité invalide", () => {
  const current = correction(["establishment.activityTypes"]);
  assert.throws(() => buildCorrectionFieldPatch(current, {
    "establishment.activityTypes": {types: ["Autre"], other: ""},
  }, fv, requestId), /Autre/);
  assert.throws(() => buildCorrectionFieldPatch(current, {
    "establishment.activityTypes": {types: ["inconnue"], other: ""},
  }, fv, requestId), /Activités invalides/);
});

test("décision Super Admin : champs et rubriques restent cohérents", () => {
  const original = {
    status: "pending",
    contactEmail: "candidate@example.test",
  };
  const cmd = {
    decision: "changes_requested",
    reason: "Corrigez votre nom et les activités.",
    fields: ["identity.contactLastName", "establishment.activityTypes"],
    scopes: ["identity", "establishment"],
  };
  const patch = buildDecisionUpdate(original, cmd, fv, timestamp);
  assert.deepEqual(patch.correctionRequest.fields, cmd.fields);
  assert.deepEqual(patch.correctionRequest.scopes, cmd.scopes);
  assert.deepEqual(patch.applicationHistory.arrayUnion[0].correctionFields,
      cmd.fields);
  assert.throws(() => buildDecisionUpdate(original, {
    ...cmd, scopes: ["identity"],
  }, fv, timestamp), /incohérents/);
});

test("clés de champs reconnues et rubriques de saisie sécurisées", () => {
  assert.equal(FIELD_SCOPES["establishment.activityTypes"], "establishment");
  assert.equal(FIELD_SCOPES["identity.contactLastName"], "identity");
  assert.equal(FIELD_SCOPES["location"], "location");
});
