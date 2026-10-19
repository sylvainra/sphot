"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {approvedAssetPatch} = require("../advertiser_campaign_sync");

/**
 * Construit un dossier approuvé pour les tests de synchronisation.
 * @param {Object} overrides Champs de dossier à remplacer.
 * @return {Object} Dossier de test.
 */
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

test("une approbation ne modifie que le visuel et la position", () => {
  const before = {
    status: "approved",
    assetChangeRequest: {status: "submitted"},
  };
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
  const submitted = {
    status: "approved",
    assetChangeRequest: {status: "submitted"},
  };
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
  const submitted = {
    status: "approved",
    assetChangeRequest: {status: "submitted"},
  };
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

test("compatibilité avec les propositions historiques", () => {
  const before = {
    status: "approved",
    assetChangeRequest: {status: "submitted"},
  };
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

test("campagne active : préserver offre, prix et dates", async () => {
  const {registerAdvertiserCampaignSync} =
      require("../advertiser_campaign_sync");
  const timestamp = (millis) => ({toMillis: () => millis});
  const submittedAt = timestamp(1792410000000);
  const old = {
    status: "approved",
    assetChangeRequest: {status: "submitted", submittedAt},
  };
  const approved = {
    status: "approved",
    application: {destinationUrl: "https://shop.example.org/"},
    assetChangeRequest: {
      ...dossier().assetChangeRequest,
      submittedAt,
    },
  };
  const requestRef = {path: "advertiserRequests/request-1"};
  const historyWrites = [];
  const updates = [];
  const campaign = {
    status: "active",
    advertiserRequestId: "request-1",
    visibilityType: "pack",
    broadcastType: "local",
    bannerUrl: "https://example.com/old.jpg",
    centerLat: 46.2,
    centerLng: -1.2,
    campaignStartDate: "2026-10-19",
    campaignEndDate: "2026-10-25",
    totalPriceExclTax: 129,
  };
  const adRef = {
    id: "campaign-1",
    path: "adRequests/campaign-1",
    collection: (name) => ({
      doc: (id) => ({path: "adRequests/campaign-1/" + name + "/" + id}),
    }),
  };
  const adDoc = {exists: true, id: "campaign-1", ref: adRef,
    data: () => campaign};
  const db = {
    collection: () => ({
      where: () => ({
        limit: () => ({get: async () => ({docs: [adDoc]})}),
      }),
      doc: () => ({get: async () => ({exists: false})}),
    }),
    runTransaction: async (run) => run({
      get: async (ref) => ref === requestRef ?
        ({data: () => approved}) : adDoc,
      update: (ref, values) => updates.push({ref, values}),
      set: (ref, values) => historyWrites.push({ref, values}),
    }),
  };
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "server-time"};
  const handler = registerAdvertiserCampaignSync({
    admin: {firestore},
    onDocumentUpdated: (_, fn) => fn,
  });
  await handler({
    id: "unique-firebase-event",
    params: {requestId: "request-1"},
    data: {
      before: {data: () => old},
      after: {data: () => approved, ref: requestRef},
    },
  });
  const adWrite = updates.find((item) => item.ref === adRef);
  assert.ok(adWrite);
  assert.equal(adWrite.values.bannerUrl,
      "https://storage.example.com/new-banner.jpg");
  assert.equal(adWrite.values.centerLat, 46.39);
  assert.equal(adWrite.values.centerLng, -1.49);
  assert.equal(adWrite.values.destinationUrl, "https://shop.example.org/");
  assert.equal(adWrite.values.websiteUrl, "https://shop.example.org/");
  for (const key of ["status", "visibilityType", "campaignStartDate",
    "campaignEndDate", "totalPriceExclTax"]) {
    assert.equal(Object.hasOwn(adWrite.values, key), false);
  }
  assert.equal(historyWrites.length, 1);
  const resultWrite = updates.find((item) => item.ref === requestRef);
  assert.equal(resultWrite.values["assetChangeRequest.syncStatus"], "applied");
});
