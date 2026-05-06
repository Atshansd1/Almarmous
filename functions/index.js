const {initializeApp} = require("firebase-admin/app");
const {getMessaging} = require("firebase-admin/messaging");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const vision = require("@google-cloud/vision");

initializeApp();

const visionClient = new vision.ImageAnnotatorClient();

const STATUS_AR = {
  sent: "مرسل",
  delivered: "تم التسليم",
  returned: "مرتجع",
};

const STATUS_EN = {
  sent: "Sent",
  delivered: "Delivered",
  returned: "Returned",
};

exports.notifyOrderChange = onDocumentWritten("orders/{orderId}", async (event) => {
  if (!event.data || !event.data.after.exists) return;

  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.data();
  const oldStatus = before && before.status;
  const newStatus = after.status || "sent";

  if (before && oldStatus === newStatus) return;

  const tracking = after.trackingNumber || event.params.orderId;
  const arStatus = STATUS_AR[newStatus] || newStatus;
  const enStatus = STATUS_EN[newStatus] || newStatus;

  await getMessaging().send({
    topic: "almarmous-orders",
    notification: {
      title: "تحديث طلب / Order update",
      body: `${tracking}: ${arStatus} / ${enStatus}`,
    },
    data: {
      orderId: event.params.orderId,
      trackingNumber: String(tracking),
      status: String(newStatus),
    },
    android: {
      priority: "high",
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  });
});

exports.extractLabelText = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const imageBase64 = request.data && request.data.imageBase64;
  if (!imageBase64 || typeof imageBase64 !== "string") {
    throw new HttpsError("invalid-argument", "imageBase64 is required.");
  }

  if (Buffer.byteLength(imageBase64, "base64") > 6 * 1024 * 1024) {
    throw new HttpsError("invalid-argument", "Image is too large.");
  }

  const [result] = await visionClient.documentTextDetection({
    image: {content: imageBase64},
    imageContext: {languageHints: ["ar", "en"]},
  });

  return {text: (result.fullTextAnnotation && result.fullTextAnnotation.text) || ""};
});
