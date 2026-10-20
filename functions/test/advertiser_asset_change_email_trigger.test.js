"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  shouldNotifyAdvertiserAssetChange,
  advertiserAssetChangeNotificationId,
} = require("../advertiser_asset_change_email_trigger");

const document = (
    status, syncStatus, lastSyncAt, requestStatus = "approved",
) => ({
  status: requestStatus,
  assetChangeRequest: {status, syncStatus, lastSyncAt},
});
const time = (seconds) => ({seconds, nanoseconds: 100});

test("un brouillon de renouvellement ne déclenche pas de mail visuel", () => {
  const previous = {
    status: "approved",
    assetChangeRequest: {status: "approved", syncStatus: "applied"},
  };
  const current = {
    ...previous,
    renewalDraft: {
      status: "awaiting_commercial_checkout",
      proposedTerritory: {level: "radius_15km"},
    },
  };
  assert.equal(
      shouldNotifyAdvertiserAssetChange(previous, current), false,
  );
});

test("proposal submitted email remains available", () => {
  assert.equal(shouldNotifyAdvertiserAssetChange(
      document("authorized"), document("submitted")), true);
});

test("approval does not send before campaign sync finishes", () => {
  assert.equal(shouldNotifyAdvertiserAssetChange(
      document("submitted", "applied", time(100)),
      document("approved", "applied", time(100))), false);
});

test("first campaign sync completion sends approval email", () => {
  assert.equal(shouldNotifyAdvertiserAssetChange(
      document("approved", "pending", null),
      document("approved", "applied", time(200))), true);
});

test("second approval triggers despite an unchanged sync status", () => {
  assert.equal(shouldNotifyAdvertiserAssetChange(
      document("approved", "applied", time(100)),
      document("approved", "applied", time(200))), true);
});

test("unchanged synchronization does not send duplicate", () => {
  assert.equal(shouldNotifyAdvertiserAssetChange(
      document("approved", "applied", time(200)),
      document("approved", "applied", {seconds: 200, nanoseconds: 100})),
  false);
});

test("unknown and incomplete sync statuses do not send", () => {
  assert.equal(shouldNotifyAdvertiserAssetChange(
      document("approved", "pending", time(100)),
      document("approved", "pending", time(200))), false);
  assert.equal(shouldNotifyAdvertiserAssetChange(
      document("approved", "applied", time(100)),
      document("approved", "applied", null)), false);
});

test("unlinked and no_active_campaign synchronize normally", () => {
  for (const syncStatus of ["unlinked", "no_active_campaign"]) {
    assert.equal(shouldNotifyAdvertiserAssetChange(
        document("approved", "applied", time(100)),
        document("approved", syncStatus, time(200))), true);
  }
});

test("nonapproved accounts are ignored", () => {
  assert.equal(shouldNotifyAdvertiserAssetChange(
      document("submitted"), document("approved", "applied", time(200),
          "pending")), false);
});

test("same approved proposal has one notification key across retries", () => {
  const change = {submittedAt: time(170)};
  assert.equal(advertiserAssetChangeNotificationId(
      "approved", change, "event-one", "advertiser-1"),
  advertiserAssetChangeNotificationId(
      "approved", change, "event-two", "advertiser-1"));
});

test("later proposal gets a different notification key", () => {
  assert.notEqual(advertiserAssetChangeNotificationId(
      "approved", {submittedAt: time(170)}, "event-one", "advertiser-1"),
  advertiserAssetChangeNotificationId(
      "approved", {submittedAt: time(180)}, "event-two", "advertiser-1"));
});

test("nonapproved notifications retain their event key", () => {
  assert.equal(advertiserAssetChangeNotificationId(
      "submitted", {submittedAt: time(170)}, "event-one", "advertiser-1"),
  "event-one");
});
