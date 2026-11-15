"use strict";

const {surveillanceWindowForSauveteurs} =
  require("./sauveteur_surveillance_schedule");

const {describeFlagMast} = require("./sauveteur_flag_transition");
const {mainCouranteLifecycle} =
    require("./sauveteur_main_courante_lifecycle");

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
  const statistics = {
    inspected: 0, lowered: 0, published: 0, statusUpdated: 0,
    errors: 0, skipped: 0,
  };
  const db = firestore;
  const seenSpots = new Set();

  // Rechercher aussi les signaux complémentaires actifs lorsque le drapeau
  // principal est déjà affalé. Un même poste n'est traité qu'une fois.
  const filters = [
    ["liveFlag.flagPosition", "in", HISSE_VALUES],
    ["liveFlag.purpleFlagActive", "==", true],
    ["liveFlag.windsockActive", "==", true],
    ["statutBaignade", "in", [
      "Baignade non surveillée",
      "Baignade non surveillée temporairement",
    ]],
  ];

  for (const [field, operator, value] of filters) {
    let lastDoc = null;
    for (;;) {
      let query = db.collection("spots")
          .where(field, operator, value)
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(100);
      if (lastDoc) query = query.startAfter(lastDoc);
      const page = await query.get();
      if (page.empty) break;

      for (const candidate of page.docs) {
        if (seenSpots.has(candidate.id)) continue;
        seenSpots.add(candidate.id);
        statistics.inspected++;
        const root = candidate.data() || {};
        const territoryId = (root.territoireId || "").toString().trim();
        if (!territoryId) {
          statistics.skipped++;
          continue;
        }

        const territory = db.collection("territoires").doc(territoryId);
        const territorySpotRef = territory.collection("spots")
            .doc(candidate.id);
        const periodsRef = territory.collection("periodesSurveillance");
        const assignedRef = territorySpotRef.collection("sauveteursAffectes");

        try {
          const [spotSnapshot, periodsSnapshot, assignedSnapshot] =
            await Promise.all([
              territorySpotRef.get(), periodsRef.get(), assignedRef.get(),
            ]);
          const periods = periodsSnapshot.docs.map((doc) => ({
            id: doc.id, ...doc.data(),
          }));
          const preview = surveillanceWindowForSauveteurs(
              assignedSnapshot.docs.map((doc) => doc.data() || {}),
              periods, now, (spotSnapshot.data() || {}).timeZone,
          );
          if (preview.open &&
              root.statutBaignade !== "Baignade non surveillée") {
            statistics.skipped++;
            continue;
          }

          const journalRef = territorySpotRef.collection("mainCourante").doc();
          const auditRef = db.collection("sauveteurOperationalAudit").doc();
          const signal = await db.runTransaction(async (transaction) => {
            const rootSnapshot = await transaction.get(candidate.ref);
            const freshSpot = await transaction.get(territorySpotRef);
            const freshPeriods = await transaction.get(periodsRef);
            const freshAssigned = await transaction.get(assignedRef);
            const rootData = rootSnapshot.data() || {};
            const live = rootData.liveFlag || {};
            const raised = HISSE_VALUES.includes(
                (live.flagPosition || "").toString(),
            );
            const purple = live.purpleFlagActive === true;
            const windsock = live.windsockActive === true;

            const currentPeriod = surveillanceWindowForSauveteurs(
                freshAssigned.docs.map((doc) => doc.data() || {}),
                freshPeriods.docs.map((doc) => ({id: doc.id, ...doc.data()})),
                now, (freshSpot.data() || {}).timeZone,
            );
            // Aucun signal n'est hissé automatiquement à l'ouverture.
            // Seul le libellé du bandeau change si le drapeau est affalé.
            if (currentPeriod.open) {
              if (raised ||
                  rootData.statutBaignade !== "Baignade non surveillée") {
                return null;
              }
              transaction.set(candidate.ref, {
                statutBaignade: "Baignade non surveillée temporairement",
                // Réouverture : le pavillon sélectionné redevient visible
                // AFFALÉ au pied du mât, sans hissage automatique.
                ...(live.automaticLoweringVisual ? {liveFlag: {
                  ...live,
                  automaticLoweringVisual: null,
                }} : {}),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              }, {merge: true});
              return {mode: "status"};
            }
            if (!raised && !purple && !windsock) {
              if (rootData.statutBaignade === "Baignade non surveillée") {
                return null;
              }
              transaction.set(candidate.ref, {
                statutBaignade: "Baignade non surveillée",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              }, {merge: true});
              return {mode: "status"};
            }

            const spotInfo = freshSpot.data() || {};
            const label = (
              spotInfo.nomSecours || spotInfo.nomSphot ||
              spotInfo.idSphot || candidate.id
            ).toString().trim();
            const message =
              `Signaux numériques SPHOT du poste ${label} désactivés ` +
              "automatiquement hors période de surveillance.";
            const nowServer = admin.firestore.FieldValue.serverTimestamp();
            const correctedFlag = {
              ...live,
              flagPosition: "affale",
              purpleFlagActive: false,
              windsockActive: false,
              // Animation visuelle seulement : aucun hissage reel simule.
              automaticLoweringVisual: {
                triggeredAt: nowServer,
                // Instantané des signaux présents AVANT l'affalage.
                // Les booléens opérationnels deviennent false immédiatement,
                // mais cet instantané reste dessiné 15 s en position basse.
                flagColor: live.flagColor || null,
                mainFlagPresent: Boolean(live.flagColor),
                purpleFlagActive: purple,
                windsockActive: windsock,
              },
            };
            // La main courante décrit TOUS les signaux présents,
            // y compris le principal s'il était déjà affalé.
            const mastAtClosure = describeFlagMast(live, true);

            transaction.set(candidate.ref, {
              liveFlag: correctedFlag,
              statutBaignade: "Baignade non surveillée",
              // Ne pas annoncer un affalage lorsque seul un signal
              // complémentaire vient d'être désactivé.
              ...(raised ? {operationalAlert: {
                type: "flag_lowered",
                active: true,
                message,
                flagColor: (live.flagColor || "").toString(),
                triggeredAt: nowServer,
                endedAt: null,
                source: "automatic_surveillance_closure",
              }} : {}),
              liveUpdatedAt: nowServer,
              updatedAt: nowServer,
            }, {merge: true});

            // Après la dernière journée de saison, aucune nouvelle
            // inscription (même automatique) n'entre dans la main courante.
            const journalOpen = mainCouranteLifecycle(
                freshSpot.data() || {},
                freshAssigned.docs.map((doc) => doc.data() || {}),
                freshPeriods.docs.map((doc) => ({...doc.data(), id: doc.id})),
                now,
            ).writable;
            if (journalOpen) transaction.set(journalRef, {
              type: "Drapeau",
              description: mastAtClosure,
              actionTaken: "",
              visibility: "operational",
              occurredAt: nowServer,
              createdAt: nowServer,
              createdBy: {
                role: "SYSTÈME",
                displayName: "SPHOT (automatique)",
                automaticMainFlagLoweredByAdminSchedule: raised,
              },
              source: "automatic_surveillance_closure",
              immutableOriginal: true,
            });

            transaction.set(auditRef, {
              territoireId: territoryId,
              spotId: candidate.id,
              role: "SYSTÈME",
              login: "SPHOT_AUTO",
              changes: {liveFlag: correctedFlag},
              source: "automatic_surveillance_closure",
              createdAt: nowServer,
            });
            return {mode: "lowered", label};
          });

          if (signal?.mode === "lowered") statistics.lowered++;
          else if (signal?.mode === "status") statistics.statusUpdated++;
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
  }

  return statistics;
}

module.exports = {autoLowerClosedFlags};
