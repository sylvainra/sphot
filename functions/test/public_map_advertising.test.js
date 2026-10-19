"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  projectPublicMapAdvertisement,
} = require("../public_map_advertising");

const now = Date.parse("2026-10-18T10:00:00Z");

/**
 * Construit une campagne publicitaire active pour les tests.
 * @param {Object} overrides Champs à remplacer dans la campagne.
 * @return {Object} Campagne de test.
 */
function active(overrides = {}) {
  return {
    status: "active",
    visibilityType: "map",
    broadcastType: "local",
    centerLat: 46.4,
    centerLng: -1.5,
    radiusKm: 10,
    campaignStartDate: new Date("2026-10-17T00:00:00Z"),
    campaignEndDate: new Date("2026-10-19T00:00:00Z"),
    bannerUrl: "https://example.com/banner.webp",
    websiteUrl: "https://example.com/",
    advertiserName: "Commerçant local",
    email: "privé@example.com",
    phone: "0000000000",
    siret: "12345678901234",
    totalPriceExclTax: 999,
    ...overrides,
  };
}

test("ne renvoie que les champs publics des publicités actives", () => {
  const result = projectPublicMapAdvertisement("campaign1", active(), now);
  assert.ok(result);
  assert.equal(result.id, "campaign1");
  assert.equal(result.centerLat, 46.4);
  assert.equal(result.radiusKm, 10);
  assert.equal(result.bannerUrl, "https://example.com/banner.webp");
  assert.equal(result.destinationUrl, "https://example.com/");
  assert.equal(result.visibilityType, "map");
  for (const privateKey of ["email", "phone", "siret", "totalPriceExclTax"]) {
    assert.equal(Object.hasOwn(result, privateKey), false);
  }
});

test("rejette les campagnes absentes, désactivées, futures ou expirées", () => {
  for (const status of ["pending", "disabled", "deleted", "reported"]) {
    assert.equal(
        projectPublicMapAdvertisement("x", active({status}), now), null);
  }
  assert.equal(projectPublicMapAdvertisement("x", active({
    campaignStartDate: new Date("2026-10-19T00:00:00Z"),
  }), now), null);
  assert.equal(projectPublicMapAdvertisement("x", active({
    campaignEndDate: new Date("2026-10-18T00:00:00Z"),
  }), now), null);
  assert.equal(projectPublicMapAdvertisement("x", active({
    campaignStartDate: null,
  }), now), null);
});

test("projette Premium uniquement avec une image HTTPS", () => {
  const premium = projectPublicMapAdvertisement("x", active({
    visibilityType: "premium",
  }), now);
  assert.ok(premium);
  assert.equal(premium.visibilityType, "premium");
  assert.equal(projectPublicMapAdvertisement("x", active({
    bannerUrl: "http://example.com/banner.webp",
  }), now), null);
  assert.equal(projectPublicMapAdvertisement("x", active({
    bannerUrl: "javascript:alert(1)",
  }), now), null);
});

test("accepte les campagnes nationales sans localisation", () => {
  const result = projectPublicMapAdvertisement("x", active({
    broadcastType: "national",
    visibilityType: "pack",
    centerLat: null,
    centerLng: null,
    radiusKm: null,
  }), now);
  assert.ok(result);
  assert.equal(result.broadcastType, "national");
  assert.equal(Object.hasOwn(result, "centerLat"), false);
});

test("rejette les campagnes locales sans épicentre et rayon valides", () => {
  assert.equal(projectPublicMapAdvertisement("x", active({
    centerLat: null,
  }), now), null);
  assert.equal(projectPublicMapAdvertisement("x", active({
    centerLat: 100,
  }), now), null);
  assert.equal(projectPublicMapAdvertisement("x", active({
    radiusKm: 0,
  }), now), null);
});

test("le lien déclaré prévaut sur l'ancien site de campagne", () => {
  const result = projectPublicMapAdvertisement("x", active({
    websiteUrl: "https://sphot.app",
    destinationUrl: "https://www.surfshop-atlantique.fr",
  }), now);
  assert.equal(result.destinationUrl, "https://www.surfshop-atlantique.fr/");
});

test("n'expose pas les URL de destination dangereuses", () => {
  const result = projectPublicMapAdvertisement("x", active({
    websiteUrl: "javascript:alert(1)",
  }), now);
  assert.ok(result);
  assert.equal(result.destinationUrl, "");
});


test("API v1 conserve Carte et Pack ; v2 ajoute Premium", async () => {
  const {registerPublicMapAdvertisingEndpoint} =
      require("../public_map_advertising");
  const start = new Date(Date.now() - 3600000);
  const end = new Date(Date.now() + 3600000);
  const rows = ["map", "premium", "pack"].map((visibilityType) => ({
    id: visibilityType,
    data: () => active({
      visibilityType,
      campaignStartDate: start,
      campaignEndDate: end,
    }),
  }));
  const admin = {
    firestore: () => ({
      collection: () => ({
        where: () => ({
          limit: () => ({
            get: async () => ({docs: rows}),
          }),
        }),
      }),
    }),
  };
  const onRequest = (_, callback) => callback;
  /**
   * Interroge l'endpoint public avec une réponse simulée.
   * @param {boolean} includePremium Inclure les campagnes Premium.
   * @return {Promise<string[]>} Types de diffusion retournés.
   */
  async function call(includePremium) {
    const handler = registerPublicMapAdvertisingEndpoint({
      admin, onRequest, includePremium,
    });
    const response = {
      headers: {},
      set(key, value) {
        this.headers[key] = value;
        return this;
      },
      status(code) {
        this.statusCode = code;
        return this;
      },
      json(data) {
        this.body = data;
        return this;
      },
      send(data) {
        this.body = data;
        return this;
      },
    };
    await handler({method: "GET"}, response);
    assert.equal(response.statusCode, 200);
    return response.body.advertisements.map((ad) => ad.visibilityType);
  }
  assert.deepEqual(await call(false), ["map", "pack"]);
  assert.deepEqual(await call(true), ["map", "pack", "premium"]);
});
