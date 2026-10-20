"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {advertiserChangeEmailStatus} =
    require("../advertiser_radius_change_email_trigger");

test("radius-only submission sends deferred radius notice", () => {
  assert.equal(advertiserChangeEmailStatus(
      {radiusChangeRequest: {status: ""}},
      {radiusChangeRequest: {status: "waiting_period_end"}},
      false,
  ), "radius_waiting");
});

test("mixed request sends one visual/position proposal email", () => {
  assert.equal(advertiserChangeEmailStatus(
      {assetChangeRequest: {status: "approved"}},
      {assetChangeRequest: {status: "submitted"},
        radiusChangeRequest: {status: "waiting_period_end"}},
      true,
  ), "submitted");
});

test("unrelated Firestore update does not send a radius email", () => {
  const document = {radiusChangeRequest: {status: "waiting_period_end"}};
  assert.equal(advertiserChangeEmailStatus(document, document, false), null);
});

test("radius may be authorized only for future paid period", () => {
  assert.equal(advertiserChangeEmailStatus(
      {radiusChangeRequest: {status: "waiting_period_end"}},
      {radiusChangeRequest: {status: "approved_pending_payment"}},
      false,
  ), "radius_approved_pending_payment");
});

test("no automatic email for untouched proposal", () => {
  assert.equal(advertiserChangeEmailStatus({}, {}, false), null);
});
