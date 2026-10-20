"use strict";

/**
 * Compare Firestore timestamps by value (not by object identity).
 * @param {*} value Firestore Timestamp or a simple test value.
 * @return {string} Stable representation.
 */
function timestampKey(value) {
  if (value == null) return "";
  if (typeof value.seconds === "number" &&
      typeof value.nanoseconds === "number") {
    return `${value.seconds}:${value.nanoseconds}`;
  }
  if (typeof value.toMillis === "function") {
    return String(value.toMillis());
  }
  return String(value);
}

/**
 * An approved change is notified only when campaign synchronization finishes.
 * A previous approval may already have the same syncStatus ("applied"), so
 * testing only a change of syncStatus silently drops later approval emails.
 * @param {Object} before Document before the Firestore event.
 * @param {Object} after Document after the Firestore event.
 * @return {boolean} Whether this event should enqueue an email.
 */
function shouldNotifyAdvertiserAssetChange(before, after) {
  const previous = (before || {}).assetChangeRequest || {};
  const current = (after || {}).assetChangeRequest || {};
  if ((after || {}).status !== "approved") return false;
  if (current.status !== "approved") {
    return Boolean(current.status) && previous.status !== current.status;
  }
  const terminal = ["applied", "unlinked", "no_active_campaign"];
  if (!terminal.includes(current.syncStatus)) return false;
  // The Super Admin's submitted -> approved write keeps the previous
  // sync status/date. Only the synchronizer's subsequent write advances it.
  if (previous.status !== "approved") return false;
  const beforeAt = timestampKey(previous.lastSyncAt);
  const afterAt = timestampKey(current.lastSyncAt);
  return afterAt !== "" && afterAt !== beforeAt;
}

/**
 * Keep one claim key when Firebase retries the same approved proposal.
 * The next submittedAt represents a different modification.
 * @param {string} status Status of the current proposal.
 * @param {Object} change Asset change request data.
 * @param {string} eventId Firestore event identifier.
 * @param {string} requestId Advertiser request ID.
 * @return {string} Stable notification ID.
 */
function advertiserAssetChangeNotificationId(
    status, change, eventId, requestId,
) {
  if (status !== "approved") return eventId;
  const version = timestampKey((change || {}).submittedAt) ||
      timestampKey((change || {}).reviewedAt);
  return version ? `${requestId}:approved:${version}` : eventId;
}

module.exports = {
  shouldNotifyAdvertiserAssetChange,
  advertiserAssetChangeNotificationId,
};
