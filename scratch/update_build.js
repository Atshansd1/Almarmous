
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function updateBuild() {
  const docRef = db.collection('appConfig').doc('mobile');
  await docRef.set({
    latestBuildNumber: 5,
    minimumBuildNumber: 4,
    androidUpdateUrl: 'https://github.com/Atshansd1/Almarmous/releases/latest',
    iosUpdateUrl: 'https://testflight.apple.com/join/...'
  }, { merge: true });
  console.log('Build updated to 5');
}

updateBuild().then(() => process.exit(0)).catch(err => { console.error(err); process.exit(1); });
