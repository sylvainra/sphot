"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  iso3, spotCountry, countryCampaignCoversSpot,
} = require("../advertiser_country_coverage");

const france = {
  advertisingTerritory: {
    level: "country",
    coverageModel: "country_whole_v1",
    countryIso3: "FRA",
  },
};

test("French coastal beaches remain eligible outside simplified red outline",
    () => {
  const beaches = [
    {idSphot: "LONGE06", pays: "France", sphotLat: 46.4, sphotLng: -1.5},
    {idSphot: "ATLANTIC", countryIso3: "FRA", sphotLat: 46.41, sphotLng: -1.6},
    {
      idSphot: "MEDITERRANEAN",
      countryIso3: "FRA",
      sphotLat: 43.2,
      sphotLng: 5.5,
    },
  ];
  for (const spot of beaches) {
    assert.equal(countryCampaignCoversSpot(france, spot), true);
  }
});

test("French national campaign does not reach another country", () => {
  assert.equal(countryCampaignCoversSpot(france, {
    countryIso3: "ESP", sphotLat: 41.39, sphotLng: 2.17,
  }), false);
});

test("Any country works with validated ISO3 metadata", () => {
  const japan = {
    advertisingTerritory: {
      level: "country", coverageModel: "country_whole_v1", code: "JPN",
    },
  };
  assert.equal(countryCampaignCoversSpot(japan, {
    countryIso3: "JPN", sphotLat: 35.6, sphotLng: 139.7,
  }), true);
  assert.equal(countryCampaignCoversSpot(japan, {
    countryIso3: "FRA", sphotLat: 35.6, sphotLng: 139.7,
  }), false);
});

test("Unknown place is flagged as unknown and cannot be guessed", () => {
  assert.equal(spotCountry({pays: "???"}), "");
  assert.equal(countryCampaignCoversSpot(france, {sphotLat: 46.4}), false);
  assert.equal(iso3("XXX"), "");
});

test("A 500 km legacy campaign cannot gain national rights", () => {
  assert.equal(countryCampaignCoversSpot({
    advertisingTerritory: {
      level: "radius_500km", coverageModel: "worldwide_radius_v2",
      countryIso3: "FRA",
    },
  }, {pays: "France"}), false);
});

test("Country campaign requires a validated coverage type and ISO code", () => {
  assert.equal(countryCampaignCoversSpot({
    advertisingTerritory: {
      level: "country", coverageModel: "country_whole_v1",
      countryIso3: "?",
    },
  }, {pays: "France"}), false);
});
