"use strict";

/**
 * Scénario Firestore Emulator (aucun accès possible à la production).
 * Rejoue l'approbation sur des données de démonstration isolées, puis
 * vérifie la synchronisation et la projection publique Carte/Premium/Pack.
 */
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {
  registerAdvertiserCampaignSync,
} = require("../advertiser_campaign_sync");
const {
  projectPublicMapAdvertisement,
} = require("../public_map_advertising");

const projectId = "demo-sphot-publicitaire";
const requestId = "demo-sphot-publicitaire-annonceur";
const modes = ["map", "premium", "pack"];
const oldBanner = "https://placehold.co/1800x300/274472/ffffff/png?text=ANCIEN+VISUEL";
const testBanner = process.env.SPHOT_TEST_BANNER_URL ||
    "https://placehold.co/1800x300/004d7a/ffffff/png?text=SPHOT+VISUEL+APPROUVE";
const testDestination = process.env.SPHOT_TEST_DESTINATION_URL ||
    "https://www.surfshop-atlantique.fr";
const advertiserName = "SURF SHOP ATLANTIQUE · TEST EMULATEUR";

async function run() {
  const host = process.env.FIRESTORE_EMULATOR_HOST || "";
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) {
    throw new Error("FIRESTORE_EMULATOR_HOST local obligatoire. " +
        "Refus d'acceder a un vrai projet Firebase.");
  }
  if (!testBanner.startsWith("https://")) {
    throw new Error("SPHOT_TEST_BANNER_URL doit commencer par https://");
  }
  if (!/^https?:\/\/[^\s/]+/i.test(testDestination)) {
    throw new Error("SPHOT_TEST_DESTINATION_URL doit etre une adresse web valide.");
  }
  if (admin.apps.length === 0) admin.initializeApp({projectId});
  const db = admin.firestore();
  const now = Date.now();
  const start = admin.firestore.Timestamp.fromMillis(now - 60 * 60 * 1000);
  const end = admin.firestore.Timestamp.fromMillis(now + 24 * 60 * 60 * 1000);
  const center = {centerLat: 46.38940535819475,
    centerLng: -1.493413525704352};

  const request = db.collection("advertiserRequests").doc(requestId);
  const campaigns = db.collection("adRequests");
  const initialRequest = {
    status: "approved",
    advertiserName: advertiserName,
    advertisingSpot: {latitude: center.centerLat,
      longitude: center.centerLng, bannerUrl: oldBanner},
    assetChangeRequest: {status: "idle"},
  };
  await request.set(initialRequest);

  for (const mode of modes) {
    await campaigns.doc("demo-sphot-" + mode).set({
      status: "active",
      advertiserRequestId: requestId,
      advertiserName: advertiserName,
      visibilityType: mode,
      broadcastType: "local",
      ...center,
      radiusKm: 5,
      campaignStartDate: start,
      campaignEndDate: end,
      bannerUrl: oldBanner,
      destinationUrl: testDestination,
      websiteUrl: testDestination,
      totalPriceExclTax: 129,
    });
  }
  await campaigns.doc("demo-sphot-disabled").set({
    status: "disabled", advertiserRequestId: requestId,
    visibilityType: "pack", broadcastType: "local",
    ...center, radiusKm: 5,
    campaignStartDate: start, campaignEndDate: end, bannerUrl: oldBanner,
  });

  // L'annonceur dépose sa proposition : aucune publication avant décision.
  const submittedAt = admin.firestore.Timestamp.now();
  await request.update({
    assetChangeRequest: {
      status: "submitted",
      submittedAt,
      proposedVisual: {url: testBanner, width: 1800, height: 300},
      proposedLocation: {latitude: center.centerLat + 0.001,
        longitude: center.centerLng + 0.001},
    },
  });
  const submitted = await request.get();
  for (const mode of modes) {
    const ad = await campaigns.doc("demo-sphot-" + mode).get();
    assert.equal(ad.data().bannerUrl, oldBanner,
        "Une proposition en attente ne doit pas etre diffusee.");
  }
  console.log("OK : proposition soumise, trois campagnes inchangees.");

  // Simulation d'une decision Super Admin portant sur cette proposition.
  await request.update({
    "assetChangeRequest.status": "approved",
    "assetChangeRequest.reviewedAt":
      admin.firestore.FieldValue.serverTimestamp(),
  });
  const approved = await request.get();

  // Execute le VRAI gestionnaire de synchronisation sur Firestore Emulator.
  // Le declencheur Firestore lui-meme n'est pas necessaire dans cet essai.
  const sync = registerAdvertiserCampaignSync({
    admin,
    onDocumentUpdated: (_settings, handler) => handler,
  });
  await sync({
    id: "local-approval-" + Date.now(),
    params: {requestId},
    data: {before: submitted, after: approved},
  });

  const checked = await request.get();
  assert.equal(checked.data().assetChangeRequest.syncStatus, "applied");
  assert.equal(checked.data().assetChangeRequest.syncedCampaignCount, 3);

  for (const mode of modes) {
    const ad = await campaigns.doc("demo-sphot-" + mode).get();
    const current = ad.data();
    assert.equal(current.bannerUrl, testBanner);
    assert.equal(current.status, "active");
    assert.equal(current.visibilityType, mode);
    assert.equal(current.radiusKm, 5);
    assert.equal(current.totalPriceExclTax, 129);
    assert.equal(current.destinationUrl, testDestination);
    assert.equal(current.campaignStartDate.toMillis(), start.toMillis());
    assert.equal(current.campaignEndDate.toMillis(), end.toMillis());
    assert.equal(current.centerLat, center.centerLat + 0.001);
    assert.equal(current.centerLng, center.centerLng + 0.001);
    const projected = projectPublicMapAdvertisement(
        ad.id, current, Date.now());
    assert.ok(projected, mode + " doit etre diffusable.");
    assert.equal(projected.visibilityType, mode);
    assert.equal(projected.bannerUrl, testBanner);
    assert.equal(projected.destinationUrl, testDestination);
    assert.equal("totalPriceExclTax" in projected, false);
    const history = await ad.ref.collection("approvedAssetChanges").get();
    assert.equal(history.size, 1, "Un seul document historique.");
    console.log("OK : " + mode + " actif, visuel approuve et historique.");
  }
  const disabled = await campaigns.doc("demo-sphot-disabled").get();
  assert.equal(disabled.data().bannerUrl, oldBanner);
  console.log("OK : campagne desactivee preservee.");
  console.log("SUCCESS : campagne de demonstration prete pour l'affichage.");
  console.log("VISUEL UTILISE : " + testBanner);
  await admin.app().delete();
}

run().catch((error) => {
  console.error("ECHEC DU TEST EMULATEUR :", error);
  process.exitCode = 1;
});
