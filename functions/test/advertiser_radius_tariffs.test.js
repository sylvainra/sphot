"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  LEVELS, OFFERS, DURATIONS, PRICE_KEYS, initialPrices,
} = require("../advertiser_radius_tariffs");

const referencePath = path.join(
    __dirname, "../../docs",
    "REFERENCE_108_TARIFS_SPHOT_PUBLICITAIRE_2026-10-18.csv");
const referenceText = fs.readFileSync(referencePath, "utf8");
const zoneLabels = [
  "5 km", "15 km", "50 km", "150 km", "300 km", "PAYS ENTIER",
];
const offerLabels = ["CARTE SPHOT", "FICHES SPHOT", "PACK TOTAL"];

test("Approved CSV exactly matches the 108 server tariff cells", () => {
  const rows = referenceText.replace(/^\uFEFF/, "").trim().split(/\r?\n/);
  assert.equal(rows.length, 19);
  assert.equal(rows[0],
      "Zone;Offre;1 semaine;2 semaines;1 mois;2 mois;6 mois;1 an");
  assert.equal(LEVELS.length, 6);
  assert.equal(OFFERS.length, 3);
  assert.equal(DURATIONS.length, 6);

  const imported = {};
  for (const line of rows.slice(1)) {
    const cells = line.split(";");
    assert.equal(cells.length, 8);
    const z = zoneLabels.indexOf(cells[0]);
    const o = offerLabels.indexOf(cells[1]);
    assert.notEqual(z, -1);
    assert.notEqual(o, -1);
    for (let d = 0; d < 6; d++) {
      assert.match(cells[2 + d], /^[0-9]+$/);
      imported[z + ":" + o + ":" + d] = Number(cells[2 + d]);
    }
  }
  const expected = initialPrices();
  assert.equal(Object.keys(imported).length, 108);
  assert.deepEqual(Object.keys(imported).sort(), PRICE_KEYS);
  assert.deepEqual(imported, expected);
  assert.equal(expected["5:2:5"], 11900);
});

test("User-approved tariff seed is never mutable across calls", () => {
  const one = initialPrices();
  one["0:0:0"] = 999999;
  assert.equal(initialPrices()["0:0:0"], 49);
});
