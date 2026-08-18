const admin = require("firebase-admin");

admin.initializeApp();

async function rebuildPublicSpots() {
  const db = admin.firestore();
  const statuses = ["trial", "active"];
  const subscriptions = [];

  for (const status of statuses) {
    const snapshot = await db.collection("subscriptions")
        .where("status", "==", status)
        .get();
    subscriptions.push(...snapshot.docs);
  }

  for (let index = 0; index < subscriptions.length; index += 450) {
    const batch = db.batch();
    subscriptions.slice(index, index + 450).forEach((document) => {
      batch.set(
          document.ref,
          {
            publicProjectionRefreshAt:
              admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
    });
    await batch.commit();
  }

  console.log(
      `${subscriptions.length} abonnement(s) transmis ` +
      "à la projection publique.",
  );
}

rebuildPublicSpots()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
