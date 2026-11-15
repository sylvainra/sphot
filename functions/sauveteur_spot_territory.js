"use strict";

/**
 * Attach a territory to an existing operational spot after its Admin save.
 * Never create a new operational spot and never overwrite a different owner.
 * This is an ordinary-save fix, not a migration of historical spots.
 *
 * @param {Object} db Firestore Admin SDK database.
 * @param {string} territoireId Authenticated territory document ID.
 * @param {string} spotId Operational spot document ID.
 * @return {Promise<string>} Result of the association attempt.
 */
async function attachOperationalSpotTerritory(db, territoireId, spotId) {
  const territory = (territoireId || "").toString().trim();
  const spot = (spotId || "").toString().trim();
  if (!territory || !spot) {
    throw new Error("missing_spot_territory_identity");
  }

  const reference = db.collection("spots").doc(spot);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return "operational_spot_absent";

    const existing = (snapshot.data()?.territoireId || "")
        .toString().trim();
    if (existing === territory) return "already_associated";
    if (existing) return "territory_conflict";

    transaction.set(reference, {territoireId: territory}, {merge: true});
    return "associated";
  });
}

module.exports = {attachOperationalSpotTerritory};
