const {initializeApp} = require("firebase-admin/app");
const {getMessaging} = require("firebase-admin/messaging");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");

initializeApp();

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
