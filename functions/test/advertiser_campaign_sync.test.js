"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {approvedAssetPatch} = require("../advertiser_campaign_sync");

function dossier(overrides = {}) {
  return {
    status: "approved",
    assetChangeRequest: {
      status: "approved",
      proposedVisual: {url: "https://storage.example.com/new-banner.jpg"},
      proposedLocation: {latitude: 46.39, longitude: -1.49},
    },
    ...overrides,
  };
}

test("une approbation du visuel et de la position produit uniquement ces champs", () => {
  const before = {status: "approved", assetChangeRequest: {status: "submitted"}};
  const patch = approvedAssetPatch(before, dossier());
  assert.deepEqual(patch, {
    bannerUrl: "https://storage.example.com/new-banner.jpg",
    centerLat: 46.39,
    centerLng: -1.49,
  });
  assert.equal(Object.hasOwn(patch, "visibilityType"), false);
  assert.equal(Object.hasOwn(patch, "status"), false);
  assert.equal(Object.hasOwn(patch, "campaignEndDate"), false);
});

test("aucune synchronisation avant approbation ou en cas de refus", () => {
  const submitted = {status: "approved", assetChangeRequest: {status: "submitted"}};
  assert.equal(approvedAssetPatch(submitted, {
    ...dossier(),
    assetChangeRequest: {...dossier().assetChangeRequest, status: "submitted"},
  }), null);
  assert.equal(approvedAssetPatch(submitted, {
    ...dossier(),
    assetChangeRequest: {...dossier().assetChangeRequest, status: "rejected"},
  }), null);
  assert.equal(approvedAssetPatch({status: "pending", assetChangeRequest: {
    status: "submitted",
  }}, dossier()), null);
});

test("rejette une image non HTTPS et une localisation impossible", () => {
  const submitted = {status: "approved", assetChangeRequest: {status: "submitted"}};
  assert.equal(approvedAssetPatch(submitted, dossier({
    assetChangeRequest: {
      ...dossier().assetChangeRequest,
      proposedVisual: {url: "http://example.com/banner.png"},
    },
  })), null);
  assert.equal(approvedAssetPatch(submitted, dossier({
    assetChangeRequest: {
      ...dossier().assetChangeRequest,
      proposedLocation: {latitude: 100, longitude: 0},
    },
  })), null);
});

test("compatibilité avec les propositions déjà soumises sous les champs historiques", () => {
  const before = {status: "approved", assetChangeRequest: {status: "submitted"}};
  const after = {
    status: "approved",
    assetChangeRequest: {status: "approved"},
    proposedVisual: {url: "https://example.com/legacy.jpg"},
    applicantLocation: {latitude: 46.4, longitude: -1.5},
  };
  assert.deepEqual(approvedAssetPatch(before, after), {
    bannerUrl: "https://example.com/legacy.jpg",
    centerLat: 46.4,
    centerLng: -1.5,
  });
});
