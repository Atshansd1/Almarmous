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
exports.checkLowStock = onDocumentWritten("products/{productId}", async (event) => {
  if (!event.data || !event.data.after.exists) return;

  const after = event.data.after.data();
  const name = after.name || "منتج";
  const qty = after.qty || 0;
  const lowThreshold = after.lowStockThreshold || 10;
  const criticalThreshold = after.criticalStockThreshold || 5;

  if (qty > lowThreshold) return;

  let title = "تنبيه مخزون / Stock Alert";
  let body = `${name}: ${qty} pieces remaining / تبقى ${qty} قطع`;
  
  if (qty <= criticalThreshold) {
    title = "⚠️ تنبيه مخزون حرج / CRITICAL Stock Alert";
    body = `CRITICAL: ${name} is almost out! Only ${qty} left. / مخزون حرج: ${name} شارف على الانتهاء! بقي ${qty} فقط.`;
  }

  await getMessaging().send({
    topic: "almarmous-admin",
    notification: {
      title: title,
      body: body,
    },
    data: {
      productId: event.params.productId,
      type: "low_stock",
      qty: String(qty),
    },
    android: {
      priority: "high",
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  });
});
exports.updateCustomerStats = onDocumentWritten("orders/{orderId}", async (event) => {
  if (!event.data || !event.data.after.exists) return;

  const after = event.data.after.data();
  const phone = after.phone;
  if (!phone) return;

  const db = event.data.after.ref.firestore;
  const customerRef = db.collection("customers").doc(phone);

  const ordersSnapshot = await db.collection("orders").where("phone", "==", phone).get();
  
  let totalOrders = 0;
  let totalSpent = 0;
  let lastOrderDate = null;

  ordersSnapshot.forEach((doc) => {
    const data = doc.data();
    totalOrders++;
    totalSpent += (data.cod || 0);
    const date = data.createdAt ? (data.createdAt.toDate ? data.createdAt.toDate() : new Date(data.createdAt)) : null;
    if (date && (!lastOrderDate || date > lastOrderDate)) {
      lastOrderDate = date;
    }
  });

  await customerRef.set({
    phone: phone,
    name: after.customerName || "",
    city: after.city || "",
    area: after.area || "",
    totalOrders: totalOrders,
    totalSpent: totalSpent,
    lastOrderDate: lastOrderDate,
    updatedAt: new Date(),
  }, {merge: true});
});
