"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {evaluateRenewal, validateRenewalTerritory} =
    require("../advertiser_renewal_rules");

const start = Date.parse("2026-10-19T00:00:00+02:00");
const end = Date.parse("2026-10-20T23:59:00+02:00");

function campaign(overrides = {}) {
  return {
    status: "active",
    campaignStartDate: {toMillis: () => start},
    campaignEndDate: {toMillis: () => end},
    ...overrides,
  };
}

test("rayon verrouillé jusqu'à la dernière minute payée", () => {
  const result = evaluateRenewal([campaign()], end - 1);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "period_in_progress");
  assert.equal(result.endAt, end);
});

test("rayon déverrouillé exactement après l'échéance serveur", () => {
  const result = evaluateRenewal([campaign()], end);
  assert.equal(result.eligible, true);
  assert.equal(result.reason, "period_finished");
});

test("statut active oublié ne maintient pas la diffusion après fin", () => {
  assert.equal(evaluateRenewal([campaign()], end + 3600000).eligible, true);
});

test("plusieurs campagnes : la dernière échéance prime", () => {
  const later = campaign({
    campaignEndDate: {toMillis: () => end + 86400000},
  });
  assert.equal(
      evaluateRenewal([campaign(), later], end + 1000).eligible,
      false,
  );
  assert.equal(
      evaluateRenewal([campaign(), later], end + 86400000).eligible,
      true,
  );
});

test("aucune campagne vérifiable : refus fermé", () => {
  assert.deepEqual(evaluateRenewal([], end + 1000), {
    eligible: false,
    reason: "no_linked_campaign",
    endAt: null,
  });
});

test("date inconnue : impossible d'autoriser le nouveau rayon", () => {
  const result = evaluateRenewal([
    campaign({campaignEndDate: null}),
  ], end + 1000000);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "invalid_campaign_period");
});

test("une campagne future empêche le renouvellement prématuré", () => {
  assert.equal(evaluateRenewal([
    campaign(),
    campaign({
      campaignStartDate: {toMillis: () => end + 1},
      campaignEndDate: {toMillis: () => end + 604800000},
    }),
  ], end + 1).eligible, false);
});

test("un dossier deleted n'est pas une période future à prolonger", () => {
  const result = evaluateRenewal([
    campaign(),
    campaign({
      status: "deleted",
      campaignEndDate: {toMillis: () => end + 604800000},
    }),
  ], end);
  assert.equal(result.eligible, true);
});

test("seuls les cinq rayons contractuels peuvent être préparés", () => {
  assert.deepEqual(validateRenewalTerritory({level: "radius_15km"}), {
    level: "radius_15km",
    code: "WORLD_radius_15km",
    name: "15 km",
    radiusKm: 15,
    coverageModel: "worldwide_radius_v2",
  });
  assert.throws(() =>
    validateRenewalTerritory({level: "radius_999km"}));
  assert.throws(() =>
    validateRenewalTerritory({level: "country", code: "FRA"}));
});
