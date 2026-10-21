"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const source = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

test("mail de correction PHASE 2 reconnue", () => {
  const start = source.indexOf("const isCorrection = status");
  const stop = source.indexOf("const applicantUrl", start);
  assert.ok(start > 0 && stop > start);
  assert.ok(source.slice(start, stop).includes(
      `assetChangeStatus === "changes_requested"`));
});

test("lien personnel de correction PHASE 2 accepte", () => {
  const start = source.indexOf("const accessible = status");
  const end = source.indexOf("const hashesMatch", start);
  assert.ok(start > 0 && end > start);
  assert.ok(source.slice(start, end).includes(
      `assetStatus === "changes_requested"`));
  const marker = "modificationRequested = status";
  const next = source.indexOf("const firebaseToken", end);
  assert.ok(source.slice(end, next).includes(marker));
  assert.ok(source.slice(end, next).includes(
      `assetStatus === "changes_requested"`));
});

test("les trois services serveur restent exportes", () => {
  assert.ok(source.includes("exports.resubmitAdvertiserCorrection ="));
  assert.ok(source.includes("exports.saveAdvertiserPhaseTwo ="));
  assert.ok(source.includes("exports.reviewAdvertiserDecision ="));
});
