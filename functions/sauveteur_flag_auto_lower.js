"use strict";

const {surveillanceWindow} = require("./sauveteur_surveillance_schedule");

const HISSE_VALUES = ["hisse", "hissé", "Hissé", "Hisse"];

/**
 * Affale le signal numérique SPHOT en dehors de sa plage Admin.
 * Les écritures (état public, audit et main courante) sont atomiques et
 * idempotentes en cas de double déclenchement de Cloud Scheduler.
 * Aucune présence humaine ni manœuvre physique n'est prétendue.
 *
 * @param {Object} firestore FirebaseFirestore administrateur.
 * @param {Object} admin SDK Firebase Admin.
 * @param {Date} now Instant de la vérification.
 * @return {Promise<Object>} Résultats à journaliser.
 */
async function autoLowerClosedFlags(firestore, admin, now = new Date()) {
  const statistics = {inspected: 0, lowered: 0, errors: 0, skipped: 0};
  const db = firestore;
  let lastDoc = null;

  // La requête cible seulement les drapeaux hissés et non les autres SPHOT.
  for (;;) {
    let query = db.collection("spots")
        .where("liveFlag.flagPosition", "in", HISSE_VALUES)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(100);
    if (lastDoc) query = query.startAfter(lastDoc);
    const page = await query.get();
    if (page.empty) break;

    for (const candidate of page.docs) {
      statistics.inspected++;
      const root = candidate.data() || {};
      const territoryId = (root.territoireId || "").toString().trim();
      if (!territoryId) {
        statistics.skipped++;
        continue;
      }

      const territory = db.collection("territoires").doc(territoryId);
      const territorySpotRef = territory.collection("spots").doc(candidate.id);
      const periodsRef = territory.collection("periodesSurveillance");

      try {
        // Vérification préalable pour éviter les transactions inutiles.
        const [spotSnapshot, periodsSnapshot] = await Promise.all([
          territorySpotRef.get(), periodsRef.get(),
        ]);
        const data = spotSnapshot.data() || {};
        const periods = periodsSnapshot.docs.map((doc) => ({
          id: doc.id, ...doc.data(),
        }));
        const preview = surveillanceWindow(data, periods, now);
        if (!preview.configured || preview.open) {
          statistics.skipped++;
          continue;
        }

        const journalRef = territorySpotRef.collection("mainCourante").doc();
        const auditRef = db.collection("sauveteurOperationalAudit").doc();
        const signal = await db.runTransaction(async (transaction) => {
          const rootSnapshot = await transaction.get(candidate.ref);
          const freshSpot = await transaction.get(territorySpotRef);
          const freshPeriods = await transaction.get(periodsRef);
          const live = (rootSnapshot.data() || {}).liveFlag || {};
          if (!HISSE_VALUES.includes(
              (live.flagPosition || "").toString())) return null;

          const currentPeriod = surveillanceWindow(
              freshSpot.data() || {},
              freshPeriods.docs.map((doc) => ({id: doc.id, ...doc.data()})),
              new Date(),
          );
          if (!currentPeriod.configured || currentPeriod.open) return null;

          const spotInfo = freshSpot.data() || {};
          const label = (
            spotInfo.nomSecours || spotInfo.nomSphot ||
            spotInfo.idSphot || candidate.id
          ).toString().trim();
          const message =
            `Signal SPHOT du poste ${label} affalé automatiquement ` +
            "à la fermeture de la période de surveillance.";
          const nowServer = admin.firestore.FieldValue.serverTimestamp();
          const originalColor = (live.flagColor || "").toString();

          transaction.set(candidate.ref, {
            liveFlag: {...live, flagPosition: "affale"},
            statutBaignade: "Baignade non surveillée temporairement",
            operationalAlert: {
              type: "flag_lowered",
              active: true,
              message,
              flagColor: originalColor,
              triggeredAt: nowServer,
              endedAt: null,
              source: "automatic_surveillance_closure",
            },
            liveUpdatedAt: nowServer,
            updatedAt: nowServer,
          }, {merge: true});

          transaction.set(journalRef, {
            type: "Drapeau",
            description:
              "Position du signal SPHOT : Hissé → Affalé " +
              "(automatique, fin de surveillance programmée). " +
              "Ne constitue pas une constatation de manœuvre physique.",
            actionTaken: "Fermeture automatique programmée par SPHOT",
            visibility: "operational",
            occurredAt: nowServer,
            createdAt: nowServer,
            createdBy: {
              role: "SYSTÈME",
              displayName: "SPHOT (automatique)",
            },
            source: "automatic_surveillance_closure",
            immutableOriginal: true,
          });

          transaction.set(auditRef, {
            territoireId: territoryId,
            spotId: candidate.id,
            role: "SYSTÈME",
            login: "SPHOT_AUTO",
            changes: {
              liveFlag: {...live, flagPosition: "affale"},
            },
            source: "automatic_surveillance_closure",
            createdAt: nowServer,
          });
          return {label};
        });

        if (signal) statistics.lowered++;
        else statistics.skipped++;
      } catch (error) {
        statistics.errors++;
        console.error("Erreur affalage automatique SPHOT:", {
          territoryId, spotId: candidate.id, message: error.message,
        });
      }
    }

    lastDoc = page.docs[page.docs.length - 1];
    if (page.size < 100) break;
  }

  return statistics;
}

module.exports = {autoLowerClosedFlags};
