"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  projectPublicMapAdvertisement,
  campaignWithApprovedAdvertiser,
  campaignsWithLinkedAdvertisers,
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


test("le dossier approuvé fournit le bon site au Pack de test", () => {
  const campaign = active({
    visibilityType: "pack",
    advertiserRequestId: "request-1",
    destinationUrl: "https://sphot.app",
    bannerUrl: "https://example.com/old-image.jpg",
    testPack: {
      previousVisibilityType: "map",
      expiresAt: new Date(now + 3600000),
    },
  });
  const dossier = {
    status: "approved",
    application: {
      destinationUrl: "https://www.mairie-longevillesurmer.fr/",
    },
    approvedApplication: {
      visual: {
        url: "https://example.com/approved-1800x300.jpg",
        webBannerUrl: "https://example.com/approved-1800x140.jpg",
      },
    },
  };
  const enriched = campaignWithApprovedAdvertiser(campaign, dossier, now);
  const projected = projectPublicMapAdvertisement("campaign", enriched, now);
  assert.equal(projected.destinationUrl,
      "https://www.mairie-longevillesurmer.fr/");
  assert.equal(projected.bannerUrl,
      "https://example.com/approved-1800x300.jpg");
  assert.equal(projected.webBannerUrl,
      "https://example.com/approved-1800x140.jpg");
  assert.equal(projected.visibilityType, "pack");
});

test("sans dossier approuvé, la campagne originale reste intacte", () => {
  const campaign = active({
    destinationUrl: "https://example.com/original",
  });
  const pending = {
    status: "pending",
    application: {destinationUrl: "https://example.com/unapproved"},
    proposedVisual: {url: "https://example.com/new-image.jpg"},
  };
  const enriched = campaignWithApprovedAdvertiser(
      campaign, pending, now);
  assert.equal(enriched, campaign);
  assert.equal(enriched.destinationUrl,
      "https://example.com/original");
});

test("l'image non approuvée ne remplace jamais l'annonce active", () => {
  const campaign = active({
    visibilityType: "pack",
    testPack: {
      previousVisibilityType: "map",
      expiresAt: new Date(now + 60000),
    },
  });
  const advertiser = {
    status: "approved",
    proposedVisual: {url: "https://example.com/pending.jpg"},
    application: {
      destinationUrl: "https://www.mairie-longevillesurmer.fr/",
    },
  };
  const enriched = campaignWithApprovedAdvertiser(
      campaign, advertiser, now);
  assert.equal(enriched.bannerUrl, campaign.bannerUrl);
  assert.equal(enriched.destinationUrl,
      "https://www.mairie-longevillesurmer.fr/");
});

test("la lecture enrichit uniquement une campagne liée par identifiant",
    async () => {
      const linked = active({
        advertiserRequestId: "existing-request",
      });
      const unrelated = active({advertiserRequestId: ""});
      const requested = [];
      const db = {
        collection: (name) => {
          if (name !== "advertiserRequests") return {};
          return {
            doc: (id) => ({
              get: async () => {
                requested.push(id);
                return {
                  exists: true,
                  data: () => ({
                    status: "approved",
                    application: {
                      destinationUrl:
                          "https://www.mairie-longevillesurmer.fr/",
                    },
                  }),
                };
              },
            }),
          };
        },
      };
      const campaigns = await campaignsWithLinkedAdvertisers(db, [
        {id: "linked", data: () => linked},
        {id: "other", data: () => unrelated},
      ], now);
      assert.deepEqual(requested, ["existing-request"]);
      assert.equal(campaigns[0].data.destinationUrl,
          "https://www.mairie-longevillesurmer.fr/");
      assert.equal(campaigns[1].data.destinationUrl, undefined);
    });
