import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  runApp(const AlmarmousApp());
}

Future<void> initializeFirebase() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await GoogleSignIn.instance.initialize();
}

class Brand {
  static const name = 'المرموس';
  static const englishName = 'Almarmous';
  static const whatsapp = '97154111752';
  static const gold = Color(0xFFC8A24A);
  static const ink = Color(0xFF171717);
  static const paper = Color(0xFFFAF8F2);
}

enum OrderStatus { sent, delivered, returned }

enum UserRole { admin, staff, driver }

extension UserRoleX on UserRole {
  String get key => switch (this) {
    UserRole.admin => 'admin',
    UserRole.staff => 'staff',
    UserRole.driver => 'driver',
  };

  static UserRole fromKey(String key) => switch (key) {
    'staff' => UserRole.staff,
    'driver' => UserRole.driver,
    _ => UserRole.admin,
  };
}

extension OrderStatusX on OrderStatus {
  String get key => switch (this) {
    OrderStatus.sent => 'sent',
    OrderStatus.delivered => 'delivered',
    OrderStatus.returned => 'returned',
  };

  Color get color => switch (this) {
    OrderStatus.sent => const Color(0xFF2563EB),
    OrderStatus.delivered => const Color(0xFF079669),
    OrderStatus.returned => const Color(0xFFDC2626),
  };

  static OrderStatus fromKey(String key) => switch (key) {
    'delivered' => OrderStatus.delivered,
    'returned' => OrderStatus.returned,
    _ => OrderStatus.sent,
  };
}

enum ProductType {
  shemagh('شماغ'),
  ghutra('غترة');

  const ProductType(this.label);
  final String label;

  static ProductType fromKey(String key) =>
      ProductType.values.firstWhere((e) => e.name == key, orElse: () => ProductType.shemagh);
}

class Customer {
  const Customer({
    required this.phone,
    required this.name,
    this.city = '',
    this.area = '',
    this.lastOrderDate,
  });

  final String phone;
  final String name;
  final String city;
  final String area;
  final DateTime? lastOrderDate;

  Map<String, Object?> toJson() => {
    'phone': phone,
    'name': name,
    'city': city,
    'area': area,
    'lastOrderDate': lastOrderDate?.toIso8601String(),
  };

  static Customer fromJson(Map<String, Object?> json) => Customer(
    phone: json['phone'] as String? ?? '',
    name: json['name'] as String? ?? '',
    city: json['city'] as String? ?? '',
    area: json['area'] as String? ?? '',
    lastOrderDate: _parseDate(json['lastOrderDate']),
  );

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is String) return DateTime.tryParse(val);
    if (val is Timestamp) return val.toDate();
    return null;
  }
}

class Product {
  static const lowStockThreshold = 10;
  static const criticalStockThreshold = 5;

  const Product({
    required this.id,
    required this.name,
    required this.type,
    required this.sizes,
    required this.price,
    required this.qty,
  });

  final String id;
  final String name;
  final ProductType type;
  final List<int> sizes;
  final double price;
  final int qty;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'sizes': sizes,
    'price': price,
    'qty': qty,
  };

  static Product fromJson(Map<String, Object?> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    type: ProductType.fromKey(json['type'] as String? ?? ''),
    sizes: (json['sizes'] as List?)?.cast<int>() ?? [],
    price: (json['price'] as num?)?.toDouble() ?? 0,
    qty: json['qty'] as int? ?? 0,
  );
}

class OfferItem {
  const OfferItem({
    required this.productType,
    required this.qty,
    required this.size,
  });

  final ProductType productType;
  final int qty;
  final int size;

  Map<String, Object?> toJson() => {
    'productType': productType.name,
    'qty': qty,
    'size': size,
  };

  static OfferItem fromJson(Map<String, Object?> json) => OfferItem(
    productType: ProductType.fromKey(json['productType'] as String? ?? ''),
    qty: json['qty'] as int? ?? 0,
    size: json['size'] as int? ?? 0,
  );
}

class Offer {
  const Offer({
    required this.id,
    required this.name,
    required this.items,
    required this.totalPrice,
  });

  final String id;
  final String name;
  final List<OfferItem> items;
  final double totalPrice;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'items': items.map((e) => e.toJson()).toList(),
    'totalPrice': totalPrice,
  };

  static Offer fromJson(Map<String, Object?> json) => Offer(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    items: (json['items'] as List?)?.map((e) => OfferItem.fromJson(Map<String, Object?>.from(e as Map))).toList() ?? [],
    totalPrice: (json['totalPrice'] as num?)?.toDouble() ?? 0,
  );
}

class OrderItem {
  const OrderItem({
    required this.name,
    required this.qty,
    required this.size,
    required this.price,
    this.offerId,
  });

  final String name;
  final int qty;
  final int size;
  final double price;
  final String? offerId;

  Map<String, Object?> toJson() => {
    'name': name,
    'qty': qty,
    'size': size,
    'price': price,
    'offerId': offerId,
  };

  static OrderItem fromJson(Map<String, Object?> json) => OrderItem(
    name: json['name'] as String? ?? '',
    qty: json['qty'] as int? ?? 0,
    size: json['size'] as int? ?? 0,
    price: (json['price'] as num?)?.toDouble() ?? 0,
    offerId: json['offerId'] as String?,
  );
}

class Order {
  const Order({
    required this.id,
    required this.trackingNumber,
    required this.phone,
    required this.city,
    required this.area,
    required this.cod,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.customerName = '',
    this.rawText = '',
    this.labelImagePath = '',
    this.timeline = const [],
    this.items = const [],
  });

  final String id;
  final String trackingNumber;
  final String phone;
  final String city;
  final String area;
  final double cod;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String customerName;
  final String rawText;
  final String labelImagePath;
  final List<String> timeline;
  final List<OrderItem> items;

  Order copyWith({
    String? trackingNumber,
    String? phone,
    String? city,
    String? area,
    double? cod,
    OrderStatus? status,
    String? customerName,
    String? rawText,
    String? labelImagePath,
    List<String>? timeline,
    List<OrderItem>? items,
  }) {
    final nextStatus = status ?? this.status;
    final nextTimeline = [
      ...this.timeline,
      if (nextStatus != this.status)
        '${DateTime.now().toIso8601String()}|status_${nextStatus.key}',
    ];
    return Order(
      id: id,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      area: area ?? this.area,
      cod: cod ?? this.cod,
      status: nextStatus,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      customerName: customerName ?? this.customerName,
      rawText: rawText ?? this.rawText,
      labelImagePath: labelImagePath ?? this.labelImagePath,
      timeline: timeline ?? nextTimeline,
      items: items ?? this.items,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'trackingNumber': trackingNumber,
    'phone': phone,
    'city': city,
    'area': area,
    'cod': cod,
    'status': status.key,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'customerName': customerName,
    'rawText': rawText,
    'labelImagePath': labelImagePath,
    'timeline': timeline,
    'items': items.map((e) => e.toJson()).toList(),
  };

  static Order fromJson(Map<String, Object?> json) {
    return Order(
      id: json['id'] as String,
      trackingNumber: json['trackingNumber'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      city: json['city'] as String? ?? '',
      area: json['area'] as String? ?? '',
      cod: (json['cod'] as num?)?.toDouble() ?? 0,
      status: OrderStatusX.fromKey(json['status'] as String? ?? 'sent'),
      createdAt: _dateFrom(json['createdAt']),
      updatedAt: _dateFrom(json['updatedAt']),
      customerName: json['customerName'] as String? ?? '',
      rawText: json['rawText'] as String? ?? '',
      labelImagePath: json['labelImagePath'] as String? ?? '',
      timeline: (json['timeline'] as List?)?.cast<String>() ?? const [],
      items: (json['items'] as List?)?.map((e) => OrderItem.fromJson(Map<String, Object?>.from(e as Map))).toList() ?? [],
    );
  }

  static DateTime _dateFrom(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}

class OrderStore extends ChangeNotifier {
  static const _storageKey = 'almarmous_orders_v1';
  static const _productsKey = 'almarmous_products_v1';
  static const _offersKey = 'almarmous_offers_v1';
  static const _customersKey = 'almarmous_customers_v1';
  static const _collection = 'orders';
  static const _productsCollection = 'products';
  static const _offersCollection = 'offers';
  static const _customersCollection = 'customers';
  static const _excludeDeliveryKey = 'exclude_delivery_v1';
  static const _deliveryFeeKey = 'delivery_fee_v1';
  static const double defaultDeliveryFee = 27.0;

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final List<Order> _orders = [];
  final List<Product> _products = [];
  final List<Offer> _offers = [];
  final List<Customer> _customers = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _productsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offersSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _customersSubscription;
  StreamSubscription<User?>? _authSubscription;
  User? _user;
  bool _loaded = false;
  bool _migrationStarted = false;
  bool _excludeDelivery = false;
  double _deliveryFee = defaultDeliveryFee;

  OrderStore() {
    if (Platform.isAndroid || Platform.isIOS) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        _user = user;
        if (user == null) {
          _ordersSubscription?.cancel();
          _productsSubscription?.cancel();
          _offersSubscription?.cancel();
          _customersSubscription?.cancel();
          _ordersSubscription = null;
          _productsSubscription = null;
          _offersSubscription = null;
          _customersSubscription = null;
        } else {
          _startCloudSync();
          unawaited(NotificationService.configure(user));
        }
        notifyListeners();
      });
    }
  }

  List<Order> get orders {
    final copy = [..._orders];
    copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }

  List<Product> get products => [..._products];
  List<Offer> get offers => [..._offers];
  List<Customer> get customers => [..._customers];
  bool get loaded => _loaded;
  bool get excludeDelivery => _excludeDelivery;
  double get deliveryFee => _deliveryFee;

  set excludeDelivery(bool value) {
    _excludeDelivery = value;
    unawaited(_prefs.setBool(_excludeDeliveryKey, value));
    notifyListeners();
  }

  set deliveryFee(double value) {
    _deliveryFee = value;
    unawaited(_prefs.setDouble(_deliveryFeeKey, value));
    notifyListeners();
  }

  Future<void> load() async {
    final encodedOrders = await _prefs.getString(_storageKey);
    if (encodedOrders != null) {
      final values = (jsonDecode(encodedOrders) as List);
      _orders.clear();
      _orders.addAll(values.map((v) => Order.fromJson(Map<String, Object?>.from(v as Map))));
    }

    _excludeDelivery = await _prefs.getBool(_excludeDeliveryKey) ?? false;
    _deliveryFee = await _prefs.getDouble(_deliveryFeeKey) ?? defaultDeliveryFee;

    final encodedProducts = await _prefs.getString(_productsKey);
    if (encodedProducts != null) {
      final values = (jsonDecode(encodedProducts) as List);
      _products.clear();
      _products.addAll(values.map((v) => Product.fromJson(Map<String, Object?>.from(v as Map))));
    } else {
      _products.addAll([
        Product(id: 'shemagh_1', name: 'شماغ', type: ProductType.shemagh, sizes: [55, 52], price: 100, qty: 50),
        Product(id: 'ghutra_1', name: 'غترة', type: ProductType.ghutra, sizes: [54, 52], price: 80, qty: 50),
      ]);
    }

    final encodedOffers = await _prefs.getString(_offersKey);
    if (encodedOffers != null) {
      final values = (jsonDecode(encodedOffers) as List);
      _offers.clear();
      _offers.addAll(values.map((v) => Offer.fromJson(Map<String, Object?>.from(v as Map))));
    } else {
      _offers.add(Offer(
        id: 'offer_2s3g',
        name: 'عرض 2 شماغ + 3 غترة',
        items: [
          OfferItem(productType: ProductType.shemagh, qty: 2, size: 55),
          OfferItem(productType: ProductType.ghutra, qty: 3, size: 54),
        ],
        totalPrice: 250,
      ));
    }

    final encodedCustomers = await _prefs.getString(_customersKey);
    if (encodedCustomers != null) {
      final values = (jsonDecode(encodedCustomers) as List);
      _customers.clear();
      _customers.addAll(values.map((v) => Customer.fromJson(Map<String, Object?>.from(v as Map))));
    }

    _loaded = true;
    if (Platform.isAndroid || Platform.isIOS) {
      _user = FirebaseAuth.instance.currentUser;
      if (_user != null) _startCloudSync();
    }
    notifyListeners();
  }

  Future<void> saveOrder(Order order) async {
    final index = _orders.indexWhere((item) => item.id == order.id);
    if (index == -1) {
      _orders.add(order);
    } else {
      _orders[index] = order;
    }

    // Update customer directory
    if (order.phone.isNotEmpty && order.customerName.isNotEmpty) {
      final customer = Customer(
        phone: order.phone,
        name: order.customerName,
        city: order.city,
        area: order.area,
        lastOrderDate: order.createdAt,
      );
      await saveCustomer(customer);
    }

    // Deduct stock for new orders
    if (index == -1) {
      _deductStock(order);
    }

    await _persist();
    if (_user != null && (Platform.isAndroid || Platform.isIOS)) {
      await FirebaseFirestore.instance.collection(_collection).doc(order.id).set({
        ...order.toJson(),
        'updatedBy': _user!.uid,
        'updatedByEmail': _user!.email,
        'syncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void _deductStock(Order order) {
    for (final item in order.items) {
      if (item.offerId != null) {
        final offer = _offers.firstWhere((o) => o.id == item.offerId, orElse: () => Offer(id: '', name: '', items: [], totalPrice: 0));
        for (final oItem in offer.items) {
          _updateProductQty(oItem.productType, oItem.qty);
        }
      } else {
        final type = item.name.contains('شماغ') ? ProductType.shemagh : ProductType.ghutra;
        _updateProductQty(type, item.qty);
      }
    }
  }

  void _updateProductQty(ProductType type, int amount) {
    final productIndex = _products.indexWhere((p) => p.type == type);
    if (productIndex >= 0) {
      final p = _products[productIndex];
      saveProduct(Product(
        id: p.id,
        name: p.name,
        type: p.type,
        sizes: p.sizes,
        price: p.price,
        qty: max(0, p.qty - amount),
      ));
    }
  }

  Order? findByTracking(String trackingNumber, {String? excludeId}) {
    final normalized = trackingNumber.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    for (final order in _orders) {
      if (order.id == excludeId) continue;
      if (order.trackingNumber.trim().toUpperCase() == normalized) {
        return order;
      }
    }
    return null;
  }

  Customer? findCustomerByPhone(String phone) {
    final normalized = phone.replaceAll(RegExp(r'\D'), '');
    if (normalized.isEmpty) return null;
    for (final customer in _customers) {
      if (customer.phone.replaceAll(RegExp(r'\D'), '') == normalized) {
        return customer;
      }
    }
    return null;
  }

  Map<String, int> getProductStats(DateTime start, DateTime end) {
    final stats = <String, int>{};
    for (final order in _orders) {
      if (order.createdAt.isAfter(start) && order.createdAt.isBefore(end)) {
        for (final item in order.items) {
          stats[item.name] = (stats[item.name] ?? 0) + item.qty;
        }
      }
    }
    return stats;
  }

  Future<void> removeOrder(String id) async {
    _orders.removeWhere((order) => order.id == id);
    await _persist();
    if (_user != null && (Platform.isAndroid || Platform.isIOS)) {
      await FirebaseFirestore.instance.collection(_collection).doc(id).delete();
    }
  }

  Future<void> saveProduct(Product product) async {
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      _products[index] = product;
    } else {
      _products.add(product);
    }
    await _persistProducts();
    if (_user != null && (Platform.isAndroid || Platform.isIOS)) {
      await FirebaseFirestore.instance.collection(_productsCollection).doc(product.id).set(product.toJson());
    }
  }

  Future<void> removeProduct(String id) async {
    _products.removeWhere((p) => p.id == id);
    await _persistProducts();
    if (_user != null && (Platform.isAndroid || Platform.isIOS)) {
      await FirebaseFirestore.instance.collection(_productsCollection).doc(id).delete();
    }
  }

  Future<void> saveOffer(Offer offer) async {
    final index = _offers.indexWhere((o) => o.id == offer.id);
    if (index >= 0) {
      _offers[index] = offer;
    } else {
      _offers.add(offer);
    }
    await _persistOffers();
    if (_user != null && (Platform.isAndroid || Platform.isIOS)) {
      await FirebaseFirestore.instance.collection(_offersCollection).doc(offer.id).set(offer.toJson());
    }
  }

  Future<void> removeOffer(String id) async {
    _offers.removeWhere((o) => o.id == id);
    await _persistOffers();
    if (_user != null && (Platform.isAndroid || Platform.isIOS)) {
      await FirebaseFirestore.instance.collection(_offersCollection).doc(id).delete();
    }
  }

  Future<void> saveCustomer(Customer customer) async {
    final index = _customers.indexWhere((c) => c.phone == customer.phone);
    if (index >= 0) {
      _customers[index] = customer;
    } else {
      _customers.add(customer);
    }
    await _persistCustomers();
    if (_user != null && (Platform.isAndroid || Platform.isIOS)) {
      await FirebaseFirestore.instance.collection(_customersCollection).doc(customer.phone).set(customer.toJson());
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(_storageKey, jsonEncode(_orders.map((o) => o.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _persistProducts() async {
    await _prefs.setString(_productsKey, jsonEncode(_products.map((p) => p.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _persistOffers() async {
    await _prefs.setString(_offersKey, jsonEncode(_offers.map((o) => o.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _persistCustomers() async {
    await _prefs.setString(_customersKey, jsonEncode(_customers.map((c) => c.toJson()).toList()));
    notifyListeners();
  }

  void _startCloudSync() {
    if (_ordersSubscription != null) return;
    if (!_migrationStarted && _orders.isNotEmpty) {
      _migrationStarted = true;
      unawaited(_migrateLocalData());
    }

    _ordersSubscription = FirebaseFirestore.instance.collection(_collection).orderBy('createdAt', descending: true).snapshots().listen((snapshot) async {
      _orders.clear();
      _orders.addAll(snapshot.docs.map((doc) => Order.fromJson({...doc.data(), 'id': doc.id})));
      await _persist();
    });

    _productsSubscription = FirebaseFirestore.instance.collection(_productsCollection).snapshots().listen((snapshot) async {
      _products.clear();
      _products.addAll(snapshot.docs.map((doc) => Product.fromJson({...doc.data(), 'id': doc.id})));
      await _persistProducts();
    });

    _offersSubscription = FirebaseFirestore.instance.collection(_offersCollection).snapshots().listen((snapshot) async {
      _offers.clear();
      _offers.addAll(snapshot.docs.map((doc) => Offer.fromJson({...doc.data(), 'id': doc.id})));
      await _persistOffers();
    });

    _customersSubscription = FirebaseFirestore.instance.collection(_customersCollection).snapshots().listen((snapshot) async {
      _customers.clear();
      _customers.addAll(snapshot.docs.map((doc) => Customer.fromJson({...doc.data(), 'phone': doc.id})));
      await _persistCustomers();
    });
  }

  Future<void> _migrateLocalData() async {
    final user = _user;
    if (user == null) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final order in _orders) {
      batch.set(FirebaseFirestore.instance.collection(_collection).doc(order.id), {
        ...order.toJson(),
        'updatedBy': user.uid,
        'updatedByEmail': user.email,
        'syncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    for (final product in _products) {
      batch.set(FirebaseFirestore.instance.collection(_productsCollection).doc(product.id), product.toJson());
    }
    for (final offer in _offers) {
      batch.set(FirebaseFirestore.instance.collection(_offersCollection).doc(offer.id), offer.toJson());
    }
    for (final customer in _customers) {
      batch.set(FirebaseFirestore.instance.collection(_customersCollection).doc(customer.phone), customer.toJson());
    }
    await batch.commit();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _productsSubscription?.cancel();
    _offersSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}

class NotificationService {
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;

  static Future<void> configure(User user) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    await messaging.subscribeToTopic('almarmous-orders');
    final token = await messaging.getToken();
    if (token != null) await _saveToken(user, token);
    await _tokenSubscription?.cancel();
    _tokenSubscription = messaging.onTokenRefresh.listen(
      (token) => unawaited(_saveToken(user, token)),
    );
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((_) {});
  }

  static Future<void> _saveToken(User user, String token) async {
    final safeId = '${user.uid}_${token.hashCode.abs()}';
    await FirebaseFirestore.instance
        .collection('notificationTokens')
        .doc(safeId)
        .set({
          'token': token,
          'uid': user.uid,
          'email': user.email,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'topic': 'almarmous-orders',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}

class UpdateService {
  static bool _automaticCheckDone = false;

  static Future<void> promoteCurrentVersion(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      if (build == 0) return;

      await FirebaseFirestore.instance.collection('appConfig').doc('mobile').set({
        'latestBuildNumber': build,
        'minimumBuildNumber': build - 1,
      }, SetOptions(merge: true));
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Version promoted successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  static Future<void> maybePrompt(
    BuildContext context, {
    bool automatic = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (automatic && _automaticCheckDone) return;
    if (automatic) _automaticCheckDone = true;

    final t = (String key) => AppText.of(context, key);
    if (!automatic && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('checkingUpdate'))));
    }

    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      final config = await FirebaseFirestore.instance
          .collection('appConfig')
          .doc('mobile')
          .get();
      final data = config.data() ?? const <String, dynamic>{};
      final latestBuild = (data['latestBuildNumber'] as num?)?.toInt() ?? 0;
      final minBuild = (data['minimumBuildNumber'] as num?)?.toInt() ?? 0;
      final updateUrl = Platform.isIOS
          ? data['iosUpdateUrl'] as String?
          : data['androidUpdateUrl'] as String?;
      final mustUpdate = minBuild > currentBuild;
      final hasUpdate = latestBuild > currentBuild;

      if (!hasUpdate && !mustUpdate) {
        if (!automatic && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t('updateCurrent'))));
        }
        return;
      }

      if (!context.mounted) return;
      final openUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: !mustUpdate,
        builder: (context) => AlertDialog(
          title: Text(t(mustUpdate ? 'updateRequired' : 'updateAvailable')),
          content: Text(t('updateMessage')),
          actions: [
            if (!mustUpdate)
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('later')),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('updateNow')),
            ),
          ],
        ),
      );

      if (openUpdate == true && updateUrl != null && updateUrl.isNotEmpty) {
        await launchUrl(
          Uri.parse(updateUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      if (!automatic && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('authError'))));
      }
    }
  }
}

class ParsedOrderData {
  ParsedOrderData({
    required this.trackingNumber,
    required this.phone,
    required this.city,
    required this.area,
    required this.cod,
    required this.rawText,
    this.customerName = '',
    this.labelImagePath = '',
    this.items = const [],
  });

  final String trackingNumber;
  final String phone;
  final String city;
  final String area;
  final double cod;
  final String rawText;
  final String customerName;
  final String labelImagePath;
  final List<OrderItem> items;

  ParsedOrderData copyWith({String? trackingNumber, String? labelImagePath}) {
    return ParsedOrderData(
      trackingNumber: trackingNumber ?? this.trackingNumber,
      phone: phone,
      city: city,
      area: area,
      cod: cod,
      rawText: rawText,
      customerName: customerName,
      labelImagePath: labelImagePath ?? this.labelImagePath,
      items: items,
    );
  }
}

class LabelParser {
  static ParsedOrderData parse(String text) {
    final normalized = _normalizeText(text);
    final lines = normalized
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final compact = lines.join(' ');
    final tracking = _tracking(compact);
    final phone = _phone(lines, compact, tracking);
    final cod = _cod(lines, compact, tracking, phone);
    final handwrittenLocation = _handwrittenLocation(lines);
    final customerName = _fieldFromLines(lines, ['Recipient', 'Name', 'المستلم', 'الاسم', 'اسم العميل', 'اسم المستلم']);
    final extractedItems = _extractItems(text);

    return ParsedOrderData(
      trackingNumber: tracking,
      phone: phone,
      city: handwrittenLocation.city.isNotEmpty
          ? handwrittenLocation.city
          : _fieldFromLines(lines, ['City', 'المدينة']),
      area: handwrittenLocation.area.isNotEmpty
          ? handwrittenLocation.area
          : _fieldFromLines(lines, ['Area', 'المنطقة']),
      cod: cod,
      customerName: _isLikelyLabel(customerName) ? '' : customerName,
      items: extractedItems,
      rawText: text,
    );
  }

  static List<OrderItem> _extractItems(String text) {
    final items = <OrderItem>[];
    final norm = text.toLowerCase();
    
    // Look for Shemagh
    final shemaghMatch = RegExp(r'(شماغ|shemagh)\s*(?:(\d+)\s*|مقاس\s*(\d+)|size\s*(\d+))?').firstMatch(norm);
    if (shemaghMatch != null) {
      final sizeStr = shemaghMatch.group(2) ?? shemaghMatch.group(3) ?? shemaghMatch.group(4);
      final size = int.tryParse(sizeStr ?? '55') ?? 55;
      items.add(OrderItem(name: 'شماغ', qty: 1, size: size, price: 100));
    }

    // Look for Ghotra
    final ghotraMatch = RegExp(r'(غترة|ghotra|ghutra)\s*(?:(\d+)\s*|مقاس\s*(\d+)|size\s*(\d+))?').firstMatch(norm);
    if (ghotraMatch != null) {
      final sizeStr = ghotraMatch.group(2) ?? ghotraMatch.group(3) ?? ghotraMatch.group(4);
      final size = int.tryParse(sizeStr ?? '54') ?? 54;
      items.add(OrderItem(name: 'غترة', qty: 1, size: size, price: 80));
    }

    return items;
  }

  static String _normalizeText(String text) {
    final words = text.split(RegExp(r'\s+'));
    final processedWords = words.map((word) {
      if (RegExp(r'\d').hasMatch(word) && RegExp(r'[Oo]').hasMatch(word)) {
        return word.replaceAll(RegExp(r'[Oo]'), '0');
      }
      return word;
    });
    final result = processedWords.join(' ');
    return _normalizeDigits(result)
        .replaceAll('\u06CC', 'ي')
        .replaceAll('\u0649', 'ي')
        .replaceAll('\u06A9', 'ك');
  }

  static String _normalizeDigits(String text) => text
      .replaceAll('\u0660', '0')
      .replaceAll('\u0661', '1')
      .replaceAll('\u0662', '2')
      .replaceAll('\u0663', '3')
      .replaceAll('\u0664', '4')
      .replaceAll('\u0665', '5')
      .replaceAll('\u0666', '6')
      .replaceAll('\u0667', '7')
      .replaceAll('\u0668', '8')
      .replaceAll('\u0669', '9')
      .replaceAll('\u06F0', '0')
      .replaceAll('\u06F1', '1')
      .replaceAll('\u06F2', '2')
      .replaceAll('\u06F3', '3')
      .replaceAll('\u06F4', '4')
      .replaceAll('\u06F5', '5')
      .replaceAll('\u06F6', '6')
      .replaceAll('\u06F7', '7')
      .replaceAll('\u06F8', '8')
      .replaceAll('\u06F9', '9');

  static String _tracking(String text) {
    final matches = RegExp(
      r'\b[A-Z]{1,4}\s*\d{5,}\b',
    ).allMatches(text.toUpperCase());
    for (final match in matches) {
      final value = match.group(0)!.replaceAll(RegExp(r'\s+'), '');
      if (!_isSupportNumber(value)) return value;
    }
    return '';
  }

  static String _phone(List<String> lines, String compact, String tracking) {
    // Aggressive phone regex for UAE (handwritten might miss leading 0 or have spaces)
    final phonePattern = RegExp(r'(?:\+?971|0)?5[024568]\d{7}');
    final fuzzyPattern = RegExp(r'\b5[024568]\s*\d\s*\d\s*\d\s*\d\s*\d\s*\d\s*\d\b');
    
    for (final source in [...lines, compact]) {
      final cleanSource = source.replaceAll(RegExp(r'[\s-]'), '');
      final match = phonePattern.firstMatch(cleanSource);
      if (match != null) {
        final val = match.group(0)!;
        if (!_isSupportNumber(val) && !_belongsTo(val, tracking)) return val;
      }
      
      final fuzzy = fuzzyPattern.firstMatch(source);
      if (fuzzy != null) {
        final val = fuzzy.group(0)!.replaceAll(RegExp(r'\s+'), '');
        if (!_isSupportNumber(val) && !_belongsTo(val, tracking)) return val;
      }
    }
    return '';
  }

  static String _normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('971')) return digits;
    if (digits.length == 10 && digits.startsWith('550')) {
      return '0${digits.substring(1)}';
    }
    return digits;
  }

  static double _cod(
    List<String> lines,
    String compact,
    String tracking,
    String phone,
  ) {
    const labels = [
      'Total COD',
      'COD',
      'Amount',
      'Price',
      'اجمالي الاستلام',
      'إجمالي الاستلام',
      'اجمالي التحصيل',
      'إجمالي التحصيل',
      'اجمالي الاسلام',
      'الاستلام',
      'المبلغ',
      'السعر',
      'القيمة',
      'درهم',
      'AED',
      'تحصيل',
    ];

    bool _isBlocked(double val) => [600, 500, 555, 55, 5].contains(val.toInt());

    // Collect all candidates near labels
    final candidates = <({double value, int distance})>[];
    for (final label in labels) {
      final index = compact.toLowerCase().indexOf(label.toLowerCase());
      if (index >= 0) {
        // Search a wide area around the label
        final start = (index - 50).clamp(0, compact.length);
        final end = (index + label.length + 150).clamp(0, compact.length);
        final excerpt = compact.substring(start, end);
        
        for (final match in RegExp(r'\d+(?:[.,]\d{1,2})?').allMatches(excerpt)) {
          final val = double.tryParse(match.group(0)!.replaceAll(',', '.'));
          if (val != null && val > 10 && val < 5000 && !_isBlocked(val)) {
            candidates.add((value: val, distance: (match.start - 50).abs()));
          }
        }
      }
    }

    if (candidates.isNotEmpty) {
      // Return the candidate closest to its label
      candidates.sort((a, b) => a.distance.compareTo(b.distance));
      return candidates.first.value;
    }

    // Last resort: pick the first valid number in the whole text
    final allValues = _moneyMatches(compact, tracking, phone).where((v) => v > 10 && v < 5000 && !_isBlocked(v)).toList();
    if (allValues.isNotEmpty) return allValues.first;

    return 0;
  }


  static Iterable<double> _moneyMatches(
    String text,
    String tracking,
    String phone,
  ) sync* {
    // Aggressively remove support hotline to prevent it from providing false numbers
    final searchable = text.replaceAll(RegExp(r'600\D*500\D*555'), ' ');

    // Explicitly blacklist segments of the customer support number and common misreads
    final blacklist = [
      '600', '500', '555', '55', '50', '60', '5.0', '5.00', '6.0', '6.00', '5', '6', '600500555'
    ];
    
    for (final match in RegExp(r'\d+(?:[.,]\d{1,2})?').allMatches(searchable)) {
      final raw = match.group(0)!;
      if (blacklist.contains(raw)) continue;
      if (_isSupportNumber(raw)) continue;
      if (_belongsTo(raw, tracking) || _belongsTo(raw, phone)) continue;
      final value = double.tryParse(raw.replaceAll(',', '.'));
      if (value != null && value > 0 && value < 10000) yield value;
    }
  }

  static String _fieldFromLines(List<String> lines, List<String> labels) {
    for (var i = 0; i < lines.length; i++) {
      if (!_containsAny(lines[i], labels)) continue;
      final candidates = [
        _cleanField(lines[i], labels),
        if (i > 0) _cleanField(lines[i - 1], labels),
        if (i + 1 < lines.length) _cleanField(lines[i + 1], labels),
      ].where((value) => value.isNotEmpty).toList();
      final arabic = candidates.where(_hasArabic).toList();
      if (arabic.isNotEmpty) return arabic.first;
      if (candidates.isNotEmpty) return candidates.first;
    }
    return '';
  }

  static ({String city, String area}) _handwrittenLocation(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final line = _cleanField(lines[i], const []);
      if (!_hasArabic(line)) continue;
      for (final city in _knownCities) {
        final index = line.indexOf(city);
        if (index < 0) continue;
        final before = line.substring(0, index).trim();
        final after = line.substring(index + city.length).trim();
        var area = _cleanArea(
          [before, after]
              .where((part) => part.isNotEmpty)
              .join(' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
        );

        if (area.isEmpty || area.length < 2) {
          // Look at previous and next lines for handwritten area
          final candidates = [
            if (i > 0) lines[i - 1],
            if (i + 1 < lines.length) lines[i + 1],
          ];
          for (final candidate in candidates) {
            final cleaned = _cleanField(candidate, const []);
            if (_hasArabic(cleaned) && !_containsAny(cleaned, _knownCities)) {
              final candidateArea = _cleanArea(cleaned);
              if (candidateArea.isNotEmpty) {
                area = candidateArea;
                break;
              }
            }
          }
        }

        return (city: _canonicalCity(city), area: area);
      }
    }
    return (city: '', area: '');
  }

  static const _knownCities = [
    'أبوظبي',
    'ابوظبي',
    'دبي',
    'عجمان',
    'الشارقة',
    'شارقة',
    'العين',
    'الفجيرة',
    'رأس الخيمة',
    'راس الخيمة',
    'أم القيوين',
    'ام القيوين',
  ];

  static String _canonicalCity(String city) => switch (city) {
    'ابوظبي' => 'أبوظبي',
    'شارقة' => 'الشارقة',
    'راس الخيمة' => 'رأس الخيمة',
    'ام القيوين' => 'أم القيوين',
    _ => city,
  };

  static String _cleanArea(String value) {
    var area = value;
    final noisyWords = [
      'Recipient Phone',
      'Total COD',
      'Package Price',
      'Delivery Fees',
      'Count Of Parts',
      'رقم موبايل المستلم',
      'اجمالي الاستلام',
      'إجمالي الاستلام',
      'اجمالي التحصيل',
      'إجمالي التحصيل',
      'اجمالي الاسلام',
      'قيمة الشحنة',
      'رسوم التوصيل',
      'عدد الأجزاء',
      'Total',
      'Package',
      'Delivery',
      'Fees',
      'Price',
      'Count',
      'Parts',
      'Quick',
      'as',
      'a',
      'click',
      'iFast',
      'IFas',
      'Ifas',
      'المدينة',
      'المنطقة',
      'Area',
      'City',
      'رقم التتبع',
      'Tracking Number',
      'رقم',
      'موبايل',
      'المستلم',
      'Recipient',
      'Phone',
    ];
    for (final word in noisyWords) {
      area = area.replaceAll(
        RegExp(RegExp.escape(word), caseSensitive: false, unicode: true),
        ' ',
      );
    }
    // Remove tracking numbers, phones, dates, and any general numbers
    area = area
        .replaceAll(RegExp(r'\b[A-Z]{1,4}\s*\d{5,}\b'), ' ')
        .replaceAll(RegExp(r'(?:\+?971|0)?5\d[\s-]?\d{3}[\s-]?\d{4}'), ' ')
        .replaceAll(RegExp(r'\b\d{4}-\d{2}-\d{2}\b'), ' ')
        .replaceAll(RegExp(r'\d+(?:[.,]\d+)?'), ' ')
        .replaceAll(RegExp(r'[:|\\/\-]+'), ' ');

    // CRITICAL: If the area contains Arabic, remove everything that is not Arabic or space
    if (_hasArabic(area)) {
      area = area.replaceAll(RegExp(r'[^\s\u0600-\u06FF]'), ' ');
    }

    area = area.replaceAll(RegExp(r'\s+'), ' ').trim();

    return area;
  }

  static bool _isLikelyLabel(String text) {
    if (text.isEmpty) return true;
    final labels = ['City', 'Area', 'Phone', 'المدينة', 'المنطقة', 'المستلم', 'رقم', 'موبايل'];
    for (final l in labels) {
      if (text.contains(l)) return true;
    }
    // If it's just numbers or very short, it's not a name
    if (text.length < 2) return true;
    if (RegExp(r'^\d+$').hasMatch(text)) return true;
    return false;
  }

  static String _cleanField(String text, List<String> labels) {
    var value = text;
    final removeWords = [
      ...labels,
      'Recipient Phone',
      'Package Price',
      'Delivery Fees',
      'Count Of Parts',
      'Total COD',
      'Quick as a click',
      'iFast',
      'رقم موبايل المستلم',
      'رسوم التوصيل',
      'عدد الأجزاء',
      'عدد الاجزاء',
      'اجمالي الاستلام',
      'إجمالي الاستلام',
      'سعر الشحنة',
    ];
    for (final word in removeWords) {
      value = value.replaceAll(
        RegExp(RegExp.escape(word), caseSensitive: false, unicode: true),
        ' ',
      );
    }
    value = value
        .replaceAll(RegExp(r'\b[A-Z]{1,4}\s*\d{5,}\b'), ' ')
        .replaceAll(RegExp(r'(?:\+?971|0)?5\d[\s-]?\d{3}[\s-]?\d{4}'), ' ')
        .replaceAll(RegExp(r'\b\d+(?:[.,]\d+)?\b'), ' ')
        .replaceAll(RegExp(r'[:|\\/\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value.length < 2 || _isTemplateLabel(value)) return '';
    return value;
  }

  static bool _containsAny(String text, List<String> values) {
    final lower = text.toLowerCase();
    return values.any((value) => lower.contains(value.toLowerCase()));
  }

  static bool _belongsTo(String value, String owner) {
    if (value.isEmpty || owner.isEmpty) return false;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final ownerDigits = owner.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty || ownerDigits.isEmpty) return false;
    if (digits.length < 5) return digits == ownerDigits;
    return ownerDigits.contains(digits);
  }

  static bool _isSupportNumber(String value) =>
      value.replaceAll(RegExp(r'\D'), '') == '600500555';

  static bool _hasArabic(String value) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(value);

  static bool _isTemplateLabel(String value) {
    final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    const labels = {
      'city',
      'area',
      'packageprice',
      'deliveryfees',
      'countofparts',
      'recipientphone',
      'totalcod',
    };
    return labels.contains(compact);
  }
}

class AppText {
  static const supportedLocales = [Locale('en'), Locale('ar')];

  static final values = <String, Map<String, String>>{
    'en': {
      'appTitle': 'Almarmous Orders',
      'loginTitle': 'Sign in',
      'loginSubtitle': 'Access Almarmous order tracking',
      'email': 'Email',
      'password': 'Password',
      'signIn': 'Sign in',
      'createAccount': 'Create account',
      'continueWithGoogle': 'Continue with Google',
      'logout': 'Logout',
      'authError': 'Could not complete sign in',
      'dashboard': 'Dashboard',
      'orders': 'Orders',
      'reports': 'Reports',
      'settings': 'Settings',
      'scan': 'Scan',
      'scanLabel': 'Scan label',
      'fromCamera': 'Camera',
      'fromGallery': 'Gallery',
      'manualOrder': 'Manual order',
      'barcode': 'Barcode',
      'scanBarcode': 'Scan barcode',
      'scannerStarting': 'Starting scanner...',
      'scannerError': 'Could not open the barcode scanner.',
      'quickActions': 'Quick actions',
      'all': 'All',
      'totalOrders': 'Total orders',
      'sent': 'Sent',
      'delivered': 'Delivered',
      'returned': 'Returned',
      'codTotal': 'COD total',
      'recentOrders': 'Recent orders',
      'noOrders': 'No orders yet',
      'startScan': 'Scan a label or add an order manually.',
      'tracking': 'Tracking number',
      'phone': 'Recipient phone',
      'city': 'City',
      'area': 'Area',
      'cod': 'Total COD',
      'status': 'Status',
      'date': 'Date',
      'save': 'Save',
      'delete': 'Delete',
      'search': 'Search orders',
      'language': 'Language',
      'english': 'English',
      'arabic': 'Arabic',
      'ocrFailed': 'Could not read the label. Try a clearer photo.',
      'extracted': 'Extracted from label',
      'reportSummary': 'Status summary',
      'today': 'Today',
      'thisWeek': 'This week',
      'editOrder': 'Edit order',
      'exportPdf': 'Export PDF',
      'exportExcel': 'Export Excel',
      'duplicateTitle': 'Order already exists',
      'duplicateMessage': 'This tracking number is already saved.',
      'openExisting': 'Open existing',
      'cancel': 'Cancel',
      'timeline': 'Timeline',
      'whatsapp': 'WhatsApp',
      'userRole': 'User role',
      'admin': 'Admin',
      'staff': 'Staff',
      'driver': 'Driver',
      'cloudBackup': 'Cloud backup',
      'cloudBackupHint':
          'Live Firebase sync is active. Orders update on every signed-in device.',
      'pushNotifications': 'Push notifications',
      'pushNotificationsHint':
          'This device is registered for order update notifications.',
      'appUpdate': 'App update',
      'appUpdateHint':
          'Check TestFlight or Google Play for the latest version.',
      'checkingUpdate': 'Checking for updates...',
      'updateAvailable': 'Update available',
      'updateRequired': 'Update required',
      'updateCurrent': 'You are using the latest version.',
      'updateMessage': 'A newer Almarmous Orders version is available.',
      'updateNow': 'Update now',
      'later': 'Later',
      'noPermission': 'Not allowed for this role',
      'yesterday': 'Yesterday',
      'thisMonth': 'This month',
      'inventory': 'Inventory',
      'products': 'Products',
      'offers': 'Offers',
      'qty': 'Quantity',
      'price': 'Price',
      'size': 'Size',
      'customerName': 'Customer Name',
      'addOrderItem': 'Add product or offer',
      'selectOffer': 'Select offer',
      'selectProduct': 'Select product',
      'shemagh': 'Shemagh',
      'ghutra': 'Ghotra',
      'site': 'almarmous.ae',
      'addProduct': 'Add Product',
      'addToInventory': 'Add to Inventory',
      'newProduct': 'New Product',
      'newOffer': 'Special Offer Bundle',
      'productName': 'Product Name',
      'offerName': 'Offer Name',
      'shemaghQty': 'Shemagh Qty',
      'ghutraQty': 'Ghotra Qty',
      'initialQty': 'Initial Qty',
      'createOffer': 'Create Offer',
      'lowStock': 'Low Stock',
      'critical': 'CRITICAL',
      'updateStock': 'Update Stock',
      'sold': 'sold',
      'noProductData': 'No product data for this period',
      'productType': 'Product Type',
      'availableSizes': 'Available Sizes',
      'excludeDelivery': 'Exclude Delivery Fees',
      'deliveryHint': 'Separate delivery fee from item totals',
      'deliveryFee': 'Delivery Fee',
      'last7Days': 'Orders (Last 7 Days)',
    },
    'ar': {
      'appTitle': 'طلبات المرموس',
      'loginTitle': 'تسجيل الدخول',
      'loginSubtitle': 'الدخول إلى نظام تتبع طلبات المرموس',
      'email': 'البريد الإلكتروني',
      'password': 'كلمة المرور',
      'signIn': 'دخول',
      'createAccount': 'إنشاء حساب',
      'continueWithGoogle': 'المتابعة بحساب Google',
      'logout': 'تسجيل الخروج',
      'authError': 'تعذر تسجيل الدخول',
      'dashboard': 'لوحة التحكم',
      'orders': 'الطلبات',
      'reports': 'التقارير',
      'settings': 'الإعدادات',
      'inventory': 'المخزون',
      'products': 'المنتجات',
      'offers': 'العروض',
      'qty': 'الكمية',
      'price': 'السعر',
      'size': 'المقاس',
      'customerName': 'اسم العميل',
      'addOrderItem': 'إضافة منتج أو عرض',
      'selectOffer': 'اختر العرض',
      'selectProduct': 'اختر المنتج',
      'shemagh': 'شماغ',
      'ghutra': 'غترة',
      'scan': 'مسح',
      'scanLabel': 'مسح الملصق',
      'fromCamera': 'الكاميرا',
      'fromGallery': 'الاستوديو',
      'manualOrder': 'طلب يدوي',
      'barcode': 'باركود',
      'scanBarcode': 'مسح الباركود',
      'scannerStarting': 'بدء الماسح...',
      'scannerError': 'تعذر فتح ماسح الباركود.',
      'quickActions': 'إجراءات سريعة',
      'all': 'الكل',
      'totalOrders': 'إجمالي الطلبات',
      'sent': 'مرسل',
      'delivered': 'تم التسليم',
      'returned': 'مرتجع',
      'codTotal': 'إجمالي التحصيل',
      'recentOrders': 'أحدث الطلبات',
      'noOrders': 'لا توجد طلبات بعد',
      'startScan': 'امسح ملصقاً أو أضف طلباً يدوياً.',
      'tracking': 'رقم التتبع',
      'phone': 'هاتف المستلم',
      'city': 'المدينة',
      'area': 'المنطقة',
      'cod': 'إجمالي المبلغ',
      'status': 'الحالة',
      'date': 'التاريخ',
      'save': 'حفظ',
      'delete': 'حذف',
      'search': 'بحث في الطلبات',
      'language': 'اللغة',
      'english': 'الإنجليزية',
      'arabic': 'العربية',
      'ocrFailed': 'تعذر قراءة الملصق. جرب صورة أوضح.',
      'extracted': 'تم استخراجه من الملصق',
      'reportSummary': 'ملخص الحالات',
      'today': 'اليوم',
      'thisWeek': 'هذا الأسبوع',
      'editOrder': 'تعديل الطلب',
      'exportPdf': 'تصدير PDF',
      'exportExcel': 'تصدير Excel',
      'duplicateTitle': 'الطلب موجود بالفعل',
      'duplicateMessage': 'رقم التتبع هذا محفوظ مسبقاً.',
      'openExisting': 'فتح الموجود',
      'cancel': 'إلغاء',
      'timeline': 'السجل',
      'whatsapp': 'واتساب',
      'userRole': 'صلاحية المستخدم',
      'admin': 'مدير',
      'staff': 'موظف',
      'driver': 'مندوب',
      'cloudBackup': 'نسخ احتياطي سحابي',
      'cloudBackupHint':
          'المزامنة مع Firebase مفعلة. الطلبات تظهر فوراً على كل الأجهزة المسجلة.',
      'pushNotifications': 'الإشعارات',
      'pushNotificationsHint':
          'هذا الجهاز مسجل لاستقبال إشعارات تحديث الطلبات.',
      'appUpdate': 'تحديث التطبيق',
      'appUpdateHint': 'تحقق من TestFlight أو Google Play لآخر إصدار.',
      'checkingUpdate': 'جاري التحقق من التحديثات...',
      'updateAvailable': 'يوجد تحديث',
      'updateRequired': 'التحديث مطلوب',
      'updateCurrent': 'أنت تستخدم آخر إصدار.',
      'updateMessage': 'يوجد إصدار أحدث من تطبيق طلبات المرموس.',
      'updateNow': 'تحديث الآن',
      'later': 'لاحقاً',
      'noPermission': 'غير مسموح لهذه الصلاحية',
      'yesterday': 'أمس',
      'thisMonth': 'هذا الشهر',
      'site': 'almarmous.ae',
      'addProduct': 'إضافة منتج',
      'addToInventory': 'إضافة إلى المخزون',
      'newProduct': 'منتج جديد',
      'newOffer': 'عرض خاص',
      'productName': 'اسم المنتج',
      'offerName': 'اسم العرض',
      'shemaghQty': 'كمية الشماغ',
      'ghutraQty': 'كمية الغترة',
      'initialQty': 'الكمية الأولية',
      'createOffer': 'إنشاء عرض',
      'lowStock': 'مخزون منخفض',
      'critical': 'حرج',
      'updateStock': 'تحديث المخزون',
      'sold': 'مباع',
      'noProductData': 'لا توجد بيانات منتجات لهذه الفترة',
      'productType': 'نوع المنتج',
      'availableSizes': 'المقاسات المتاحة',
      'excludeDelivery': 'استبعاد رسوم التوصيل',
      'deliveryHint': 'فصل رسوم التوصيل عن إجمالي المنتجات',
      'deliveryFee': 'رسوم التوصيل',
      'last7Days': 'الطلبات (آخر ٧ أيام)',
    },
  };

  static String of(BuildContext context, String key) {
    final lang = Localizations.localeOf(context).languageCode;
    return values[lang]?[key] ?? values['en']![key] ?? key;
  }
}

class AlmarmousApp extends StatefulWidget {
  const AlmarmousApp({super.key});

  @override
  State<AlmarmousApp> createState() => _AlmarmousAppState();
}

class _AlmarmousAppState extends State<AlmarmousApp> {
  static const _localeKey = 'almarmous_locale_v1';
  static const _roleKey = 'almarmous_role_v1';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final store = OrderStore();
  Locale locale = const Locale('ar');
  UserRole role = UserRole.admin;

  @override
  void initState() {
    super.initState();
    _loadLocale();
    _loadRole();
    store.load();
  }

  Future<void> _loadLocale() async {
    final language = await _prefs.getString(_localeKey);
    if (mounted && (language == 'ar' || language == 'en')) {
      setState(() => locale = Locale(language!));
    }
  }

  Future<void> _setLocale(Locale next) async {
    await _prefs.setString(_localeKey, next.languageCode);
    setState(() => locale = next);
  }

  Future<void> _loadRole() async {
    final value = await _prefs.getString(_roleKey);
    if (mounted && value != null) {
      setState(() => role = UserRoleX.fromKey(value));
    }
  }

  Future<void> _setRole(UserRole next) async {
    await _prefs.setString(_roleKey, next.key);
    setState(() => role = next);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: store,
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Almarmous Orders',
            locale: locale,
            supportedLocales: AppText.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            home: AuthGate(
              child: Directionality(
                textDirection: locale.languageCode == 'ar'
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: HomeShell(
                  store: store,
                  locale: locale,
                  role: role,
                  onLocaleChanged: _setLocale,
                  onRoleChanged: _setRole,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.gold,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? Brand.paper
          : null,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) return child;
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) return child;
        return const LoginPage();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandHeader(subtitle: Brand.englishName),
                      const SizedBox(height: 18),
                      Text(
                        t('loginTitle'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(t('loginSubtitle')),
                      const SizedBox(height: 18),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: t('email'),
                          prefixIcon: const Icon(CupertinoIcons.mail),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: password,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: t('password'),
                          prefixIcon: const Icon(CupertinoIcons.lock),
                        ),
                        onSubmitted: (_) => _signIn(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: loading ? null : _signIn,
                        icon: loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(CupertinoIcons.arrow_right_circle),
                        label: Text(t('signIn')),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: loading ? null : _createAccount,
                        icon: const Icon(CupertinoIcons.person_add),
                        label: Text(t('createAccount')),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: loading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata),
                        label: Text(t('continueWithGoogle')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    await _runAuthAction(
      () => FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      ),
    );
  }

  Future<void> _createAccount() async {
    await _runAuthAction(
      () => FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    await _runAuthAction(() async {
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      return FirebaseAuth.instance.signInWithCredential(credential);
    });
  }

  Future<void> _runAuthAction(Future<Object?> Function() action) async {
    setState(() => loading = true);
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      _showError(error.message ?? AppText.of(context, 'authError'));
    } on GoogleSignInException catch (error) {
      _showError(error.description ?? AppText.of(context, 'authError'));
    } catch (_) {
      _showError(AppText.of(context, 'authError'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.store,
    required this.locale,
    required this.role,
    required this.onLocaleChanged,
    required this.onRoleChanged,
    super.key,
  });

  final OrderStore store;
  final Locale locale;
  final UserRole role;
  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<UserRole> onRoleChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.maybePrompt(context, automatic: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    final pages = [
      DashboardPage(
        store: widget.store,
        onCameraScan: () => _pickAndRead(ImageSource.camera),
        onGalleryScan: () => _pickAndRead(ImageSource.gallery),
        onBarcodeScan: _scanBarcode,
        onManualAdd: () => _openEditor(),
        onStatusChanged: (order, status) =>
            widget.store.saveOrder(order.copyWith(status: status)),
      ),
      OrdersPage(
        store: widget.store,
        role: widget.role,
        onStatusChanged: (order, status) =>
            widget.store.saveOrder(order.copyWith(status: status)),
      ),
      InventoryPage(store: widget.store, role: widget.role),
      ReportsPage(store: widget.store, role: widget.role),
      SettingsPage(
        locale: widget.locale,
        role: widget.role,
        onLocaleChanged: widget.onLocaleChanged,
        onRoleChanged: widget.onRoleChanged,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(t('appTitle')),
        actions: [
          IconButton(
            tooltip: t('scanBarcode'),
            onPressed: _scanBarcode,
            icon: const Icon(CupertinoIcons.barcode_viewfinder),
          ),
          IconButton(
            tooltip: t('scanLabel'),
            onPressed: () => _showScanSheet(context),
            icon: const Icon(CupertinoIcons.camera_viewfinder),
          ),
        ],
      ),
      body: SafeArea(child: pages[index]),
      floatingActionButton: index == 2 && widget.role == UserRole.admin
          ? FloatingActionButton.extended(
              onPressed: () => _openAddProductSheet(context),
              icon: const Icon(CupertinoIcons.add),
              label: Text(t('addProduct')),
            )
          : FloatingActionButton.extended(
              onPressed: () => _showScanSheet(context),
              icon: const Icon(CupertinoIcons.camera_fill),
              label: Text(t('scan')),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(CupertinoIcons.chart_bar_alt_fill),
            label: t('dashboard'),
          ),
          NavigationDestination(
            icon: const Icon(CupertinoIcons.cube_box_fill),
            label: t('orders'),
          ),
          NavigationDestination(
            icon: const Icon(CupertinoIcons.archivebox_fill),
            label: t('inventory'),
          ),
          NavigationDestination(
            icon: const Icon(CupertinoIcons.doc_text_fill),
            label: t('reports'),
          ),
          NavigationDestination(
            icon: const Icon(CupertinoIcons.settings),
            label: t('settings'),
          ),
        ],
      ),
    );
  }

  void _openAddProductSheet(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('addToInventory'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => _AddProductSheet(store: widget.store),
                );
              },
              icon: const Icon(CupertinoIcons.cube_box),
              label: Text(t('newProduct')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => _AddOfferSheet(store: widget.store),
                );
              },
              icon: const Icon(CupertinoIcons.gift),
              label: Text(t('newOffer')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showScanSheet(BuildContext context) async {
    final t = (String key) => AppText.of(context, key);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('scanLabel'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _pickAndRead(ImageSource.camera);
              },
              icon: const Icon(CupertinoIcons.camera),
              label: Text(t('fromCamera')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _scanBarcode();
              },
              icon: const Icon(CupertinoIcons.barcode_viewfinder),
              label: Text(t('scanBarcode')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _pickAndRead(ImageSource.gallery);
              },
              icon: const Icon(CupertinoIcons.photo),
              label: Text(t('fromGallery')),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _openEditor();
              },
              icon: const Icon(CupertinoIcons.plus_app),
              label: Text(t('manualOrder')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndRead(ImageSource source) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (image == null || !mounted) return;

    final recognizer = TextRecognizer();
    try {
      final barcode = await _barcodeFromImage(image.path);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      final cloudText = await _cloudTextFromImage(image.path);

      final combinedText = [
        recognized.text,
        cloudText,
      ].where((value) => value.trim().isNotEmpty).join('\n');

      final parsed = LabelParser.parse(
        combinedText,
      ).copyWith(trackingNumber: barcode, labelImagePath: image.path);

      if (!mounted) return;
      if (combinedText.trim().isEmpty && parsed.trackingNumber.isEmpty) {
        _showError(AppText.of(context, 'ocrFailed'));
        return;
      }
      await _openEditor(parsed: parsed);
    } on PlatformException {
      if (mounted) _showError(AppText.of(context, 'ocrFailed'));
    } finally {
      await recognizer.close();
    }
  }

  Future<String> _cloudTextFromImage(String path) async {
    if (!Platform.isAndroid && !Platform.isIOS) return '';
    try {
      final bytes = await File(path).readAsBytes();
      final callable = FirebaseFunctions.instance.httpsCallable(
        'extractLabelText',
      );
      final result = await callable.call({'imageBase64': base64Encode(bytes)});
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['text'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String?> _barcodeFromImage(String path) async {
    final scanner = MobileScannerController(
      autoStart: false,
      formats: const [
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.qrCode,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
      ],
    );
    try {
      final capture = await scanner.analyzeImage(path);
      for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
        final value = barcode.rawValue?.trim();
        if (value?.isNotEmpty == true) return value;
      }
    } catch (_) {
      return null;
    } finally {
      await scanner.dispose();
    }
    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor({ParsedOrderData? parsed, Order? order}) async {
    final saved = await showModalBottomSheet<Order>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => OrderEditorSheet(parsed: parsed, order: order),
    );
    if (saved == null) return;
    final duplicate = widget.store.findByTracking(
      saved.trackingNumber,
      excludeId: saved.id,
    );
    if (duplicate != null && mounted) {
      final openExisting = await _confirmDuplicate();
      if (openExisting == true) {
        await _openEditor(order: duplicate);
      }
      return;
    }
    await widget.store.saveOrder(saved);
  }

  Future<bool?> _confirmDuplicate() {
    final t = (String key) => AppText.of(context, key);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('duplicateTitle')),
        content: Text(t('duplicateMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('openExisting')),
          ),
        ],
      ),
    );
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || !mounted) return;
    final existing = widget.store.findByTracking(code);
    if (existing != null) {
      await _openEditor(order: existing);
      return;
    }
    await _openEditor(
      parsed: ParsedOrderData(
        trackingNumber: code,
        phone: '',
        city: '',
        area: '',
        cod: 0,
        rawText: code,
      ),
    );
  }
}

class _AddProductSheet extends StatefulWidget {
  const _AddProductSheet({required this.store});
  final OrderStore store;

  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  final name = TextEditingController();
  final price = TextEditingController();
  final qty = TextEditingController();
  ProductType type = ProductType.shemagh;
  final sizes = <int>{55, 52};

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('newProduct'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: t('productName')),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ProductType>(
            value: type,
            items: ProductType.values.map((e) => DropdownMenuItem(value: e, child: Text(t(e.name.toLowerCase())))).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  type = v;
                  if (type == ProductType.shemagh) sizes.addAll([55, 52]);
                  if (type == ProductType.ghutra) sizes.addAll([54, 52]);
                });
              }
            },
            decoration: InputDecoration(labelText: t('productType')),
          ),
          const SizedBox(height: 12),
          Text(t('availableSizes'), style: const TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: [50, 52, 54, 55, 56, 58, 60, 62].map((s) {
              final isSelected = sizes.contains(s);
              return FilterChip(
                label: Text('$s'),
                selected: isSelected,
                onSelected: (v) {
                  setState(() {
                    if (v) sizes.add(s); else sizes.remove(s);
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t('price')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: qty,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t('initialQty')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: Text(t('addProduct')),
          ),
        ],
      ),
    );
  }

  void _save() {
    if (name.text.isEmpty) return;
    final p = Product(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.text,
      type: type,
      sizes: sizes.toList()..sort(),
      price: double.tryParse(price.text) ?? 100,
      qty: int.tryParse(qty.text) ?? 0,
    );
    widget.store.saveProduct(p);
    Navigator.pop(context);
  }
}

class _AddOfferSheet extends StatefulWidget {
  const _AddOfferSheet({required this.store});
  final OrderStore store;

  @override
  State<_AddOfferSheet> createState() => _AddOfferSheetState();
}

class _AddOfferSheetState extends State<_AddOfferSheet> {
  final name = TextEditingController(text: 'Special Offer');
  final price = TextEditingController(text: '250');
  int shemaghQty = 2;
  int ghutraQty = 3;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('newOffer'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: t('offerName')),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('shemaghQty')),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<int>(
                      value: shemaghQty,
                      items: List.generate(11, (i) => DropdownMenuItem(value: i, child: Text('$i'))),
                      onChanged: (v) => setState(() => shemaghQty = v ?? 0),
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('ghutraQty')),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<int>(
                      value: ghutraQty,
                      items: List.generate(11, (i) => DropdownMenuItem(value: i, child: Text('$i'))),
                      onChanged: (v) => setState(() => ghutraQty = v ?? 0),
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t('price')),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: Text(t('createOffer')),
          ),
        ],
      ),
    );
  }

  void _save() {
    if (name.text.isEmpty) return;
    final offer = Offer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.text,
      totalPrice: double.tryParse(price.text) ?? 250,
      items: [
        if (shemaghQty > 0) OfferItem(productType: ProductType.shemagh, qty: shemaghQty, size: 55),
        if (ghutraQty > 0) OfferItem(productType: ProductType.ghutra, qty: ghutraQty, size: 54),
      ],
    );
    widget.store.saveOffer(offer);
    Navigator.pop(context);
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.store,
    required this.onCameraScan,
    required this.onGalleryScan,
    required this.onBarcodeScan,
    required this.onManualAdd,
    required this.onStatusChanged,
    super.key,
  });

  final OrderStore store;
  final VoidCallback onCameraScan;
  final VoidCallback onGalleryScan;
  final VoidCallback onBarcodeScan;
  final VoidCallback onManualAdd;
  final void Function(Order order, OrderStatus status) onStatusChanged;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String range = 'today';

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    final orders = _filteredOrders(widget.store.orders).toList();
    final totalCod = orders.fold<double>(
      0,
      (total, order) => total + order.cod,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        BrandHeader(subtitle: t('site')),
        const SizedBox(height: 12),
        QuickActionsPanel(
          onCameraScan: widget.onCameraScan,
          onGalleryScan: widget.onGalleryScan,
          onBarcodeScan: widget.onBarcodeScan,
          onManualAdd: widget.onManualAdd,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'today', label: Text(t('today'))),
              ButtonSegment(value: 'yesterday', label: Text(t('yesterday'))),
              ButtonSegment(value: 'week', label: Text(t('thisWeek'))),
              ButtonSegment(value: 'month', label: Text(t('thisMonth'))),
            ],
            selected: {range},
            onSelectionChanged: (selection) =>
                setState(() => range = selection.first),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 640 ? 5 : 2;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.45,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: [
                MetricCard(
                  title: t('totalOrders'),
                  value: '${orders.length}',
                  icon: CupertinoIcons.cube_box,
                  color: Brand.ink,
                ),
                MetricCard(
                  title: t('sent'),
                  value: '${_count(orders, OrderStatus.sent)}',
                  icon: CupertinoIcons.paperplane,
                  color: OrderStatus.sent.color,
                ),
                MetricCard(
                  title: t('delivered'),
                  value: '${_count(orders, OrderStatus.delivered)}',
                  icon: CupertinoIcons.checkmark_seal,
                  color: OrderStatus.delivered.color,
                ),
                MetricCard(
                  title: t('returned'),
                  value: '${_count(orders, OrderStatus.returned)}',
                  icon: CupertinoIcons.arrow_uturn_left,
                  color: OrderStatus.returned.color,
                ),
                MetricCard(
                  title: 'Low Stock',
                  value: '${widget.store.products.where((p) => p.qty <= Product.lowStockThreshold).length}',
                  icon: CupertinoIcons.exclamationmark_triangle,
                  color: Colors.orange,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        MetricCard(
          title: t('codTotal'),
          value: NumberFormat.currency(symbol: 'AED ').format(totalCod),
          icon: CupertinoIcons.money_dollar_circle,
          color: const Color(0xFFB45309),
          wide: true,
        ),
        const SizedBox(height: 16),
        _OrdersChart(orders: widget.store.orders),
        const SizedBox(height: 22),
        Text(t('recentOrders'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (orders.isEmpty) EmptyState(message: t('startScan')),
        ...orders
            .take(6)
            .map(
              (order) => OrderTile(
                order: order,
                onStatusChanged: (status) =>
                    widget.onStatusChanged(order, status),
              ),
            ),
      ],
    );
  }

  int _count(List<Order> orders, OrderStatus status) =>
      orders.where((order) => order.status == status).length;

  Iterable<Order> _filteredOrders(List<Order> orders) {
    final now = DateTime.now();
    bool sameDay(DateTime date, DateTime target) =>
        date.year == target.year &&
        date.month == target.month &&
        date.day == target.day;

    return orders.where((order) {
      return switch (range) {
        'yesterday' => sameDay(
          order.createdAt,
          now.subtract(const Duration(days: 1)),
        ),
        'week' => order.createdAt.isAfter(
          now.subtract(Duration(days: now.weekday)),
        ),
        'month' =>
          order.createdAt.year == now.year &&
              order.createdAt.month == now.month,
        _ => sameDay(order.createdAt, now),
      };
    });
  }
}

class _OrdersChart extends StatelessWidget {
  const _OrdersChart({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).languageCode;
    final last7Days = List.generate(7, (i) {
      final date = now.subtract(Duration(days: 6 - i));
      final count = orders.where((o) => 
        o.createdAt.year == date.year && 
        o.createdAt.month == date.month && 
        o.createdAt.day == date.day
      ).length;
      final dayName = DateFormat.E(locale).format(date);
      return MapEntry(dayName, count);
    });

    final maxCount = last7Days.fold<int>(1, (max, e) => e.value > max ? e.value : max);

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppText.of(context, 'last7Days'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 130,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: last7Days.map((e) {
                  final heightFactor = e.value / maxCount;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 24,
                        height: (100 * heightFactor).clamp(4, 100).toDouble(),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        e.key,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({
    required this.store,
    required this.role,
    required this.onStatusChanged,
    super.key,
  });

  final OrderStore store;
  final UserRole role;
  final void Function(Order order, OrderStatus status) onStatusChanged;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  String query = '';
  String statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    final selectedStatus = statusFilter == 'all'
        ? null
        : OrderStatusX.fromKey(statusFilter);
    final orders = widget.store.orders.where((order) {
      if (selectedStatus != null && order.status != selectedStatus) {
        return false;
      }
      final haystack =
          '${order.trackingNumber} ${order.phone} ${order.city} ${order.area}'
              .toLowerCase();
      return haystack.contains(query.toLowerCase());
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: t('search'),
            prefixIcon: const Icon(CupertinoIcons.search),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'all', label: Text(t('all'))),
              ...OrderStatus.values.map(
                (status) => ButtonSegment(
                  value: status.key,
                  label: Text(t(status.key)),
                ),
              ),
            ],
            selected: {statusFilter},
            onSelectionChanged: (selection) =>
                setState(() => statusFilter = selection.first),
          ),
        ),
        const SizedBox(height: 12),
        if (orders.isEmpty) EmptyState(message: t('noOrders')),
        ...orders.map((order) {
          final tile = OrderTile(
            order: order,
            onStatusChanged: (status) => widget.onStatusChanged(order, status),
            onTap: () async {
              final saved = await showModalBottomSheet<Order>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => OrderEditorSheet(order: order),
              );
              if (saved != null) await widget.store.saveOrder(saved);
            },
          );
          if (widget.role != UserRole.admin) return tile;
          return Dismissible(
            key: ValueKey(order.id),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 10),
              alignment: AlignmentDirectional.centerEnd,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                CupertinoIcons.delete,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            onDismissed: (_) => widget.store.removeOrder(order.id),
            child: tile,
          );
        }),
      ],
    );
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({required this.store, required this.role, super.key});
  final OrderStore store;
  final UserRole role;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t('products')),
            Tab(text: t('offers')),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ProductsList(store: widget.store, role: widget.role),
              _OffersList(store: widget.store, role: widget.role),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductsList extends StatelessWidget {
  const _ProductsList({required this.store, required this.role});
  final OrderStore store;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    final products = store.products;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final p = products[index];
        final isCritical = p.qty <= Product.criticalStockThreshold;
        final isLow = p.qty <= Product.lowStockThreshold;
        
        final statusColor = isCritical 
            ? Colors.red 
            : (isLow ? Colors.orange : Colors.green);

        final tile = Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: statusColor.withOpacity(0.1),
              child: Icon(
                isCritical ? CupertinoIcons.exclamationmark_circle_fill : CupertinoIcons.cube_box,
                color: statusColor,
              ),
            ),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${t('qty')}: ${p.qty} | ${t('size')}: ${p.sizes.join(", ")}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${p.price} AED', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                if (isLow) 
                  Text(
                    isCritical ? 'CRITICAL' : 'LOW STOCK',
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900),
                  ),
              ],
            ),
            onTap: role == UserRole.admin ? () => _editProduct(context, p) : null,
          ),
        );

        if (role != UserRole.admin) return tile;

        return Dismissible(
          key: ValueKey(p.id),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              CupertinoIcons.delete,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          onDismissed: (_) => store.removeProduct(p.id),
          child: tile,
        );
      },
    );
  }

  void _editProduct(BuildContext context, Product product) {
    final t = (String key) => AppText.of(context, key);
    // Dialog to update QTY
    final controller = TextEditingController(text: product.qty.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${t('updateStock')}: ${product.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: t('qty')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text) ?? product.qty;
              store.saveProduct(Product(
                id: product.id,
                name: product.name,
                type: product.type,
                sizes: product.sizes,
                price: product.price,
                qty: val,
              ));
              Navigator.pop(context);
            },
            child: Text(t('save')),
          ),
        ],
      ),
    );
  }
}

class _OffersList extends StatelessWidget {
  const _OffersList({required this.store, required this.role});
  final OrderStore store;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    final offers = store.offers;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: offers.length,
      itemBuilder: (context, index) {
        final o = offers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: o.items.map((it) => Text('• ${it.qty}x ${t(it.productType.name)} (${t('size')} ${it.size})')).toList(),
            ),
            trailing: Text('${o.totalPrice} AED', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
            onTap: role == UserRole.admin ? () => _editOffer(context, o) : null,
          ),
        );
      },
    );
  }

  void _editOffer(BuildContext context, Offer offer) {
    // Basic edit dialog
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({required this.store, required this.role, super.key});

  final OrderStore store;
  final UserRole role;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String range = 'today';

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    final orders = _filteredOrders(widget.store.orders).toList();

    final totalCod = orders.fold<double>(0, (sum, o) => sum + o.cod);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t('reportSummary'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'today', label: Text(t('today'))),
              ButtonSegment(value: 'yesterday', label: Text(t('yesterday'))),
              ButtonSegment(value: 'week', label: Text(t('thisWeek'))),
              ButtonSegment(value: 'month', label: Text(t('thisMonth'))),
            ],
            selected: {range},
            onSelectionChanged: (selection) =>
                setState(() => range = selection.first),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: t('totalOrders'),
                value: '${orders.length}',
                icon: CupertinoIcons.cube_box,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                title: t('codTotal'),
                value: '${totalCod.toStringAsFixed(0)}',
                icon: CupertinoIcons.money_dollar,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(t('products'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _ProductStatsCard(orders: orders),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: widget.role == UserRole.driver
                    ? () => _showNoPermission(context)
                    : () => ReportExporter.sharePdf(context, orders),
                icon: const Icon(CupertinoIcons.doc_richtext),
                label: Text(t('exportPdf')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.role == UserRole.driver
                    ? () => _showNoPermission(context)
                    : () => ReportExporter.shareExcel(context, orders),
                icon: const Icon(CupertinoIcons.table),
                label: Text(t('exportExcel')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(t('status'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...OrderStatus.values.map(
          (status) => StatusReportBar(
            label: t(status.key),
            count: orders.where((order) => order.status == status).length,
            total: max(orders.length, 1),
            color: status.color,
          ),
        ),
      ],
    );
  }
  Iterable<Order> _filteredOrders(List<Order> orders) {
    final now = DateTime.now();
    bool sameDay(DateTime date, DateTime target) =>
        date.year == target.year &&
        date.month == target.month &&
        date.day == target.day;

    return orders.where((order) {
      return switch (range) {
        'yesterday' => sameDay(
          order.createdAt,
          now.subtract(const Duration(days: 1)),
        ),
        'week' => order.createdAt.isAfter(
          now.subtract(Duration(days: now.weekday)),
        ),
        'month' =>
            order.createdAt.year == now.year &&
                order.createdAt.month == now.month,
        _ => sameDay(order.createdAt, now),
      };
    });
  }

  void _showNoPermission(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppText.of(context, 'noPermission'))),
    );
  }
}

class _ProductStatsCard extends StatelessWidget {
  const _ProductStatsCard({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    final stats = <String, int>{};
    for (final o in orders) {
      for (final it in o.items) {
        stats[it.name] = (stats[it.name] ?? 0) + it.qty;
      }
    }

    if (stats.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(child: Text(t('noProductData'))),
        ),
      );
    }

    final sorted = stats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxValue = sorted.first.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sorted.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${e.value} ${t('sold')}'),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: e.value / max(maxValue, 1),
                  backgroundColor: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          )).toList(),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.locale,
    required this.role,
    required this.onLocaleChanged,
    required this.onRoleChanged,
    super.key,
  });

  final Locale locale;
  final UserRole role;
  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<UserRole> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t('language'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'en', label: Text(t('english'))),
            ButtonSegment(value: 'ar', label: Text(t('arabic'))),
          ],
          selected: {locale.languageCode},
          onSelectionChanged: (selection) =>
              onLocaleChanged(Locale(selection.first)),
        ),
        const SizedBox(height: 22),
        Text(t('userRole'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SegmentedButton<UserRole>(
          segments: UserRole.values
              .map(
                (item) => ButtonSegment(value: item, label: Text(t(item.key))),
              )
              .toList(),
          selected: {role},
          onSelectionChanged: (selection) => onRoleChanged(selection.first),
        ),
        const SizedBox(height: 22),
        Card(
          child: ListTile(
            leading: const Icon(CupertinoIcons.cloud_upload),
            title: Text(t('cloudBackup')),
            subtitle: Text(t('cloudBackupHint')),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(CupertinoIcons.bell),
            title: Text(t('pushNotifications')),
            subtitle: Text(t('pushNotificationsHint')),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(CupertinoIcons.money_dollar_circle),
                title: Text(t('excludeDelivery')),
                subtitle: Text(t('deliveryHint')),
                value: Provider.of<OrderStore>(context).excludeDelivery,
                onChanged: (v) => Provider.of<OrderStore>(context, listen: false).excludeDelivery = v,
              ),
              if (Provider.of<OrderStore>(context).excludeDelivery)
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(child: Text(t('deliveryFee'))),
                      SizedBox(
                        width: 100,
                        child: TextFormField(
                          initialValue: Provider.of<OrderStore>(context, listen: false).deliveryFee.toStringAsFixed(0),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            suffixText: 'AED',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          ),
                          onChanged: (v) {
                            final val = double.tryParse(v);
                            if (val != null) {
                              Provider.of<OrderStore>(context, listen: false).deliveryFee = val;
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(CupertinoIcons.arrow_down_circle),
                title: Text(t('appUpdate')),
                subtitle: Text(t('appUpdateHint')),
                trailing: const Icon(CupertinoIcons.chevron_forward),
                onTap: () => UpdateService.maybePrompt(context),
              ),
              if (role == UserRole.admin) ...[
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(CupertinoIcons.cloud_upload),
                  title: const Text('Promote current to Latest'),
                  subtitle: const Text('Broadcast this build to all devices'),
                  onTap: () => UpdateService.promoteCurrentVersion(context),
                ),
              ],
            ],
          ),
        ),
        if (Platform.isAndroid || Platform.isIOS) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(CupertinoIcons.person_crop_circle),
              title: Text(
                FirebaseAuth.instance.currentUser?.email ?? t('email'),
              ),
              trailing: TextButton.icon(
                onPressed: () async {
                  await GoogleSignIn.instance.signOut();
                  await FirebaseAuth.instance.signOut();
                },
                icon: const Icon(CupertinoIcons.square_arrow_right),
                label: Text(t('logout')),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class OrderEditorSheet extends StatefulWidget {
  const OrderEditorSheet({this.parsed, this.order, super.key});

  final ParsedOrderData? parsed;
  final Order? order;

  @override
  State<OrderEditorSheet> createState() => _OrderEditorSheetState();
}

class _OrderEditorSheetState extends State<OrderEditorSheet> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController tracking;
  late final TextEditingController phone;
  late final TextEditingController city;
  late final TextEditingController area;
  late final TextEditingController cod;
  late final TextEditingController customerName;
  late OrderStatus status;
  List<OrderItem> items = [];
  final FocusNode _codFocus = FocusNode();
  bool get _codMissing => cod.text.trim().isEmpty && widget.order == null && widget.parsed != null;

  @override
  void initState() {
    super.initState();
    final parsed = widget.parsed;
    final order = widget.order;
    tracking = TextEditingController(
      text: order?.trackingNumber ?? parsed?.trackingNumber ?? '',
    );
    phone = TextEditingController(text: order?.phone ?? parsed?.phone ?? '');
    city = TextEditingController(text: order?.city ?? parsed?.city ?? '');
    area = TextEditingController(text: order?.area ?? parsed?.area ?? '');
    customerName = TextEditingController(text: order?.customerName ?? parsed?.customerName ?? '');
    cod = TextEditingController(
      text: ((order?.cod ?? parsed?.cod ?? 0) == 0)
          ? ''
          : '${order?.cod ?? parsed?.cod}',
    );
    status = order?.status ?? OrderStatus.sent;
    items = List.from(order?.items ?? []);
    
    phone.addListener(_lookupCustomer);
    
    // Auto-focus COD if it was not extracted by OCR
    if (cod.text.isEmpty && order == null && parsed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _codFocus.requestFocus();
      });
    }
  }

  void _lookupCustomer() {
    if (phone.text.length >= 9) {
      final store = Provider.of<OrderStore>(context, listen: false);
      final customer = store.findCustomerByPhone(phone.text);
      if (customer != null && customerName.text.isEmpty) {
        setState(() {
          customerName.text = customer.name;
          if (city.text.isEmpty) city.text = customer.city;
          if (area.text.isEmpty) area.text = customer.area;
        });
      }
    }
  }

  void _checkAutoOffers() {
    // Logic to see if current items match an offer
    final store = Provider.of<OrderStore>(context, listen: false);
    final counts = <ProductType, int>{};
    for (final it in items) {
      if (it.offerId != null) continue;
      final type = it.name.contains('شماغ') ? ProductType.shemagh : ProductType.ghutra;
      counts[type] = (counts[type] ?? 0) + it.qty;
    }

    for (final offer in store.offers) {
      bool match = true;
      for (final oItem in offer.items) {
        if ((counts[oItem.productType] ?? 0) < oItem.qty) {
          match = false;
          break;
        }
      }
      if (match) {
        _showAutoOfferPrompt(offer);
        break;
      }
    }
  }

  void _showAutoOfferPrompt(Offer offer) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Apply ${offer.name} for ${offer.totalPrice} AED?'),
        action: SnackBarAction(
          label: 'Apply',
          onPressed: () {
            setState(() {
              // Remove individual items that are part of the offer
              for (final oItem in offer.items) {
                int toRemove = oItem.qty;
                items.removeWhere((it) {
                  if (toRemove > 0 && it.offerId == null && (it.name.contains('شماغ') == (oItem.productType == ProductType.shemagh))) {
                    toRemove -= it.qty;
                    return true;
                  }
                  return false;
                });
              }
              items.add(OrderItem(
                name: offer.name,
                qty: 1,
                size: 0,
                price: offer.totalPrice,
                offerId: offer.id,
              ));
              final total = items.fold<double>(0, (sum, it) => sum + it.price);
              cod.text = total.toString();
            });
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    phone.removeListener(_lookupCustomer);
    tracking.dispose();
    phone.dispose();
    city.dispose();
    area.dispose();
    cod.dispose();
    customerName.dispose();
    _codFocus.dispose();
    super.dispose();
  }

  void _addItem(OrderItem item) {
    setState(() {
      items.add(item);
      final total = items.fold<double>(0, (sum, it) => sum + it.price);
      cod.text = total.toString();
    });
    _checkAutoOffers();
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Form(
        key: formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              widget.order == null ? t('extracted') : t('editOrder'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            if (_imagePath.isNotEmpty && File(_imagePath).existsSync()) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_imagePath),
                  height: 180,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
            ],
            _field(t('tracking'), tracking, TextInputType.text),
            _field(t('customerName'), customerName, TextInputType.text),
            _field(t('phone'), phone, TextInputType.phone),
            Row(
              children: [
                Expanded(child: _field(t('city'), city, TextInputType.text)),
                const SizedBox(width: 10),
                Expanded(child: _field(t('area'), area, TextInputType.text)),
              ],
            ),
            const Divider(),
            Text(t('addOrderItem'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showOfferSelector(context),
                    icon: const Icon(CupertinoIcons.gift),
                    label: Text(t('offers')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showProductSelector(context),
                    icon: const Icon(CupertinoIcons.tag),
                    label: Text(t('products')),
                  ),
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...items.map((it) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(it.name),
                subtitle: Text('${t('size')} ${it.size} | ${it.qty}x'),
                trailing: Text('${it.price} AED'),
                leading: IconButton(
                  icon: const Icon(CupertinoIcons.minus_circle),
                  onPressed: () => setState(() {
                    items.remove(it);
                    final total = items.fold<double>(0, (sum, i) => sum + i.price);
                    cod.text = total.toString();
                  }),
                ),
              )),
            ],
            const Divider(),
            if (_codMissing) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade600),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.amber.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'لم يتم قراءة المبلغ تلقائياً — أدخله يدوياً',
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            _field(t('cod'), cod, TextInputType.number, focusNode: _codFocus),
            const SizedBox(height: 8),
            SegmentedButton<OrderStatus>(
              segments: OrderStatus.values
                  .map(
                    (item) => ButtonSegment(
                      value: item,
                      label: Text(t(item.key)),
                      icon: Icon(_statusIcon(item)),
                    ),
                  )
                  .toList(),
              selected: {status},
              onSelectionChanged: (selection) =>
                  setState(() => status = selection.first),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(CupertinoIcons.checkmark_alt),
              label: Text(t('save')),
            ),
            if (widget.order != null && widget.order!.timeline.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                t('timeline'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...widget.order!.timeline.reversed
                  .take(8)
                  .map(
                    (item) => ListTile(
                      dense: true,
                      leading: const Icon(CupertinoIcons.time),
                      title: Text(_timelineText(context, item)),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  void _showOfferSelector(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    final store = Provider.of<OrderStore>(context, listen: false);
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(t('selectOffer'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...store.offers.map((o) => ListTile(
            title: Text(o.name),
            subtitle: Text('${o.totalPrice} AED'),
            onTap: () {
              Navigator.pop(context);
              _showOfferSizeSelector(context, o);
            },
          )),
        ],
      ),
    );
  }

  void _showOfferSizeSelector(BuildContext context, Offer o) {
    final t = (String key) => AppText.of(context, key);
    final hasShemagh = o.items.any((it) => it.productType == ProductType.shemagh);
    final hasGhotra = o.items.any((it) => it.productType == ProductType.ghutra);

    int? sSize;
    int? gSize;

    void _complete() {
      if ((hasShemagh && sSize == null) || (hasGhotra && gSize == null)) return;
      
      String displayName = o.name;
      if (sSize != null && gSize != null) displayName += " (${t('shemagh')}:$sSize, ${t('ghutra')}:$gSize)";
      else if (sSize != null) displayName += " (${t('shemagh')}:$sSize)";
      else if (gSize != null) displayName += " (${t('ghutra')}:$gSize)";

      _addItem(OrderItem(
        name: displayName,
        qty: 1,
        size: sSize ?? gSize ?? 0,
        price: o.totalPrice,
        offerId: o.id,
      ));
      Navigator.pop(context);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(o.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (hasShemagh) ...[
                Text(t('shemagh'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [55, 52, 54, 56, 58].map((s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('$s'),
                        selected: sSize == s,
                        onSelected: (v) => setModalState(() => sSize = v ? s : null),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (hasGhotra) ...[
                Text(t('ghutra'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [54, 52, 56, 50].map((s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('$s'),
                        selected: gSize == s,
                        onSelected: (v) => setModalState(() => gSize = v ? s : null),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: ((hasShemagh && sSize == null) || (hasGhotra && gSize == null)) ? null : _complete,
                child: Text(t('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProductSelector(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    final store = Provider.of<OrderStore>(context, listen: false);
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(t('selectProduct'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...store.products.map((p) => ListTile(
            title: Text(p.name),
            subtitle: Text('${p.price} AED'),
            onTap: () {
              Navigator.pop(context);
              _showSizeSelector(context, p);
            },
          )),
        ],
      ),
    );
  }

  void _showSizeSelector(BuildContext context, Product p) {
    final t = (String key) => AppText.of(context, key);
    int? selected;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${t('size')} - ${p.name}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: p.sizes.map((s) => ChoiceChip(
                  label: Text('$s'),
                  selected: selected == s,
                  onSelected: (v) {
                    setModalState(() => selected = v ? s : null);
                    if (v) {
                      _addItem(OrderItem(
                        name: p.name,
                        qty: 1,
                        size: s,
                        price: p.price,
                      ));
                      Navigator.pop(context);
                    }
                  },
                )).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String get _imagePath =>
      widget.order?.labelImagePath ?? widget.parsed?.labelImagePath ?? '';

  Widget _field(
    String label,
    TextEditingController controller,
    TextInputType type, {
    FocusNode? focusNode,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: type,
        inputFormatters: type == TextInputType.number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        decoration: InputDecoration(
          labelText: label,
          errorBorder: focusNode != null && focusNode.hasFocus
              ? const OutlineInputBorder(borderSide: BorderSide(color: Colors.amber))
              : null,
        ),
      ),
    );
  }

  IconData _statusIcon(OrderStatus status) => switch (status) {
    OrderStatus.sent => CupertinoIcons.paperplane,
    OrderStatus.delivered => CupertinoIcons.checkmark_seal,
    OrderStatus.returned => CupertinoIcons.arrow_uturn_left,
  };

  void _save() {
    final now = DateTime.now();
    final existing = widget.order;
    Navigator.pop(
      context,
      Order(
        id: existing?.id ?? now.microsecondsSinceEpoch.toString(),
        trackingNumber: tracking.text.trim(),
        phone: phone.text.trim(),
        city: city.text.trim(),
        area: area.text.trim(),
        customerName: customerName.text.trim(),
        cod: double.tryParse(cod.text.trim()) ?? 0,
        status: status,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        rawText: widget.parsed?.rawText ?? existing?.rawText ?? '',
        labelImagePath: _imagePath,
        items: items,
        timeline: [
          ...?existing?.timeline,
          if (existing == null) '${now.toIso8601String()}|created',
          if (existing != null && existing.status != status)
            '${now.toIso8601String()}|status_${status.key}',
        ],
      ),
    );
  }

  String _timelineText(BuildContext context, String item) {
    final parts = item.split('|');
    final date = DateTime.tryParse(parts.first);
    final action = parts.length > 1 ? parts.last : item;
    final label = action.startsWith('status_')
        ? AppText.of(context, action.replaceFirst('status_', ''))
        : action;
    final dateText = date == null
        ? ''
        : DateFormat.yMMMd().add_jm().format(date);
    return [label, dateText].where((value) => value.isNotEmpty).join(' · ');
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.wide = false,
    super.key,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({required this.subtitle, super.key});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Brand.ink,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Brand.gold,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'م',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Brand.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuickActionsPanel extends StatelessWidget {
  const QuickActionsPanel({
    required this.onCameraScan,
    required this.onGalleryScan,
    required this.onBarcodeScan,
    required this.onManualAdd,
    super.key,
  });

  final VoidCallback onCameraScan;
  final VoidCallback onGalleryScan;
  final VoidCallback onBarcodeScan;
  final VoidCallback onManualAdd;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('quickActions'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCameraScan,
              icon: const Icon(CupertinoIcons.camera_viewfinder),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(t('fromCamera')),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onBarcodeScan,
                    icon: const Icon(CupertinoIcons.barcode_viewfinder),
                    label: FittedBox(child: Text(t('barcode'))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onGalleryScan,
                    icon: const Icon(CupertinoIcons.photo),
                    label: FittedBox(child: Text(t('fromGallery'))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onManualAdd,
              icon: const Icon(CupertinoIcons.plus_app),
              label: Text(t('manualOrder')),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderTile extends StatelessWidget {
  const OrderTile({
    required this.order,
    this.onTap,
    this.onStatusChanged,
    super.key,
  });

  final Order order;
  final VoidCallback? onTap;
  final ValueChanged<OrderStatus>? onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        title: Text(
          order.trackingNumber.isEmpty ? order.phone : order.trackingNumber,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            if (order.phone.isNotEmpty) order.phone,
            if (order.city.isNotEmpty) order.city,
            if (order.area.isNotEmpty) order.area,
            DateFormat.yMMMd().format(order.createdAt),
          ].join(' · '),
        ),
        trailing: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (order.phone.isNotEmpty)
              IconButton(
                tooltip: t('whatsapp'),
                onPressed: () => _openWhatsapp(order),
                icon: const Icon(CupertinoIcons.chat_bubble_2),
              ),
            PopupMenuButton<OrderStatus>(
              tooltip: t('status'),
              onSelected: onStatusChanged,
              itemBuilder: (context) => OrderStatus.values
                  .map(
                    (status) => PopupMenuItem(
                      value: status,
                      child: Row(
                        children: [
                          Icon(_icon(status), color: status.color),
                          const SizedBox(width: 8),
                          Text(t(status.key)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: Chip(
                label: Text(t(order.status.key)),
                avatar: Icon(_icon(order.status), size: 16),
                backgroundColor: order.status.color.withValues(alpha: 0.12),
                side: BorderSide.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWhatsapp(Order order) async {
    final phone = _normalizePhone(order.phone);
    final text = Uri.encodeComponent(
      'Almarmous order ${order.trackingNumber} - ${order.status.key}',
    );
    await launchUrl(Uri.parse('https://wa.me/$phone?text=$text'));
  }

  String _normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('971')) return digits;
    if (digits.startsWith('0')) return '971${digits.substring(1)}';
    return digits;
  }

  IconData _icon(OrderStatus status) => switch (status) {
    OrderStatus.sent => CupertinoIcons.paperplane,
    OrderStatus.delivered => CupertinoIcons.checkmark_seal,
    OrderStatus.returned => CupertinoIcons.arrow_uturn_left,
  };
}

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  late final MobileScannerController controller;
  bool handled = false;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.qrCode,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
      ],
    );
  }

  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppText.of(context, key);
    return Scaffold(
      appBar: AppBar(title: Text(t('scanBarcode'))),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            placeholderBuilder: (context) => Center(
              child: Text(
                t('scannerStarting'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
            ),
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t('scannerError'),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
            onDetect: _handleBarcode,
          ),
          Center(
            child: Container(
              width: 260,
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: Brand.gold, width: 3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (handled) return;
    String? code;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value?.isNotEmpty == true) {
        code = value;
        break;
      }
    }
    if (code == null || code.isEmpty) return;
    handled = true;
    await controller.stop();
    if (mounted) Navigator.pop(context, code);
  }
}

class ReportExporter {
  static Future<void> sharePdf(BuildContext context, List<Order> orders) async {
    final store = Provider.of<OrderStore>(context, listen: false);
    final file = await _writePdf(orders, store.excludeDelivery, store.deliveryFee);
    await _share(context, file, 'تقرير طلبات المرموس PDF');
  }

  static Future<void> shareExcel(
    BuildContext context,
    List<Order> orders,
  ) async {
    final store = Provider.of<OrderStore>(context, listen: false);
    final file = await _writeExcel(orders, store.excludeDelivery, store.deliveryFee);
    await _share(context, file, 'تقرير طلبات المرموس Excel');
  }

  static Future<File> _writePdf(List<Order> orders, bool excludeDelivery, double deliveryFee) async {
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf'),
    );
    final generatedAt = DateFormat(
      'yyyy/MM/dd - hh:mm a',
      'ar',
    ).format(DateTime.now());

    // Calculate picking stats
    final pickingStats = <String, int>{};
    for (final o in orders) {
      for (final it in o.items) {
        final key = '${it.name}${it.size > 0 ? " (مقاس ${it.size})" : ""}';
        pickingStats[key] = (pickingStats[key] ?? 0) + it.qty;
      }
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
          fontFallback: [
            pw.Font.helvetica(),
          ],
        ),
        pageFormat: pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: pdf.PdfColor.fromHex('#171717'),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'تقرير طلبات المرموس',
                  style: pw.TextStyle(
                    color: pdf.PdfColors.white,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'almarmous.ae',
                  textDirection: pw.TextDirection.ltr,
                  style: const pw.TextStyle(
                    color: pdf.PdfColors.grey300,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfSummaryBox(
                title: 'إجمالي الطلبات',
                value: '${orders.length}',
              ),
              _pdfSummaryBox(
                title: 'إجمالي التحصيل',
                value: '${_totalCod(orders).toStringAsFixed(2)} درهم',
              ),
              _pdfSummaryBox(title: 'تاريخ التقرير', value: generatedAt),
            ],
          ),
          pw.SizedBox(height: 16),
          if (pickingStats.isNotEmpty) ...[
            pw.Text(
              'قائمة التجهيز (Warehouse Picking List)',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: pdf.PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                children: pickingStats.entries.map((e) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(e.key),
                      pw.Text('${e.value} قطعة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                )).toList(),
              ),
            ),
            pw.SizedBox(height: 16),
          ],
          _pdfStatusSummary(orders),
          pw.SizedBox(height: 12),
          _pdfOrdersTable(orders, excludeDelivery, deliveryFee),
        ],
      ),
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/تقرير_طلبات_المرموس_${_fileStamp()}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static Future<File> _writeExcel(List<Order> orders, bool excludeDelivery, double deliveryFee) async {
    final workbook = xlsio.Workbook();
    workbook.isRightToLeft = true;
    final sheet = workbook.worksheets[0];
    sheet.name = 'تقرير الطلبات';
    sheet.isRightToLeft = true;

    sheet.getRangeByName('A1:L1').merge();
    sheet.getRangeByName('A1').setText('تقرير طلبات المرموس - Almarmous Orders Report');
    sheet.getRangeByName('A1').cellStyle
      ..bold = true
      ..fontSize = 18
      ..fontColor = '#FFFFFF'
      ..backColor = '#171717'
      ..hAlign = xlsio.HAlignType.center;

    sheet.getRangeByName('A2:L2').merge();
    sheet
        .getRangeByName('A2')
        .setText(
          'Report Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
        );
    sheet.getRangeByName('A2').cellStyle
      ..hAlign = xlsio.HAlignType.center
      ..fontColor = '#6B6257';

    sheet.getRangeByName('A4').setText('إجمالي الطلبات (Total Orders)');
    sheet.getRangeByName('B4').setNumber(orders.length.toDouble());
    sheet.getRangeByName('C4').setText('إجمالي التحصيل (Total COD)');
    sheet.getRangeByName('D4').setNumber(_totalCod(orders));
    sheet.getRangeByName('E4').setText('مرسل (Sent)');
    sheet.getRangeByName('F4').setNumber(_count(orders, OrderStatus.sent).toDouble());
    sheet.getRangeByName('G4').setText('تم التسليم (Delivered)');
    sheet.getRangeByName('H4').setNumber(_count(orders, OrderStatus.delivered).toDouble());
    
    sheet.getRangeByName('A4:L4').cellStyle
      ..bold = true
      ..backColor = '#F6E5B8'
      ..hAlign = xlsio.HAlignType.center;

    final headers = [
      'Tracking Number (رقم التتبع)',
      'Customer Name (الاسم)',
      'Phone (الهاتف)',
      'City (المدينة)',
      'Area (المنطقة)',
      'Items Net Value (سعر الأصناف)',
      'Delivery Fee (رسوم التوصيل)',
      'Total COD (التحصيل)',
      'Status (الحالة)',
      'Order Items (الأصناف)',
      'Created (تاريخ الإنشاء)',
      'Updated (آخر تحديث)',
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(6, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle
        ..bold = true
        ..fontColor = '#FFFFFF'
        ..backColor = '#806109'
        ..hAlign = xlsio.HAlignType.center;
    }

    for (var i = 0; i < orders.length; i++) {
      final o = orders[i];
      final itemsText = o.items.map((it) => '${it.qty}x ${it.name} (${it.size})').join(', ');
      final row = i + 7;
      final deliveryValue = excludeDelivery ? deliveryFee : 0.0;
      final itemPrice = o.cod - deliveryValue;

      sheet.getRangeByIndex(row, 1).setText(o.trackingNumber);
      sheet.getRangeByIndex(row, 2).setText(o.customerName);
      sheet.getRangeByIndex(row, 3).setText(o.phone);
      sheet.getRangeByIndex(row, 4).setText(o.city);
      sheet.getRangeByIndex(row, 5).setText(o.area);
      sheet.getRangeByIndex(row, 6).setNumber(itemPrice);
      sheet.getRangeByIndex(row, 7).setNumber(deliveryValue);
      sheet.getRangeByIndex(row, 8).setNumber(o.cod);
      sheet.getRangeByIndex(row, 9).setText(o.status.key);
      sheet.getRangeByIndex(row, 10).setText(itemsText);
      sheet.getRangeByIndex(row, 11).setText(DateFormat('yyyy-MM-dd').format(o.createdAt));
      sheet.getRangeByIndex(row, 12).setText(DateFormat('yyyy-MM-dd').format(o.updatedAt));
    }

    // Auto-fit columns
    for (var i = 1; i <= headers.length; i++) {
      sheet.autoFitColumn(i);
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/تقرير_طلبات_المرموس_${_fileStamp()}.xlsx');
    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();
    await file.writeAsBytes(bytes);
    return file;
  }


  static pw.Widget _pdfSummaryBox({
    required String title,
    required String value,
  }) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 3),
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          color: pdf.PdfColor.fromHex('#FAF8F2'),
          border: pw.Border.all(color: pdf.PdfColor.fromHex('#E4D7BC')),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pdfStatusSummary(List<Order> orders) {
    return pw.Table(
      border: pw.TableBorder.all(color: pdf.PdfColor.fromHex('#E4D7BC')),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: pdf.PdfColor.fromHex('#806109')),
          children: [
            'الحالة',
            'العدد',
          ].map((text) => _pdfCell(text, header: true)).toList(),
        ),
        ...OrderStatus.values.map(
          (status) => pw.TableRow(
            children: [
              _pdfCell(_statusAr(status)),
              _pdfCell('${_count(orders, status)}'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _pdfOrdersTable(List<Order> orders, bool excludeDelivery, double deliveryFee) {
    final headers = [
      'رقم التتبع',
      'المدينة',
      'المنطقة',
      'الأصناف',
      'التحصيل',
      'الحالة',
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: pdf.PdfColor.fromHex('#E4D7BC')),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(0.8),
        2: pw.FlexColumnWidth(0.8),
        3: pw.FlexColumnWidth(2),
        4: pw.FlexColumnWidth(0.8),
        5: pw.FlexColumnWidth(0.8),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: pdf.PdfColor.fromHex('#806109')),
          children: headers
              .map((text) => _pdfCell(text, header: true))
              .toList(),
        ),
        ...orders.map((order) {
          final itemsText = order.items.map((it) => '${it.qty}x ${it.name} (${it.size})').join(', ');
          return pw.TableRow(
            children: [
              _pdfCell(order.trackingNumber),
              _pdfCell(order.city),
              _pdfCell(order.area),
              _pdfCell(itemsText),
              _pdfCell('${order.cod.toStringAsFixed(0)}'),
              _pdfCell(_statusAr(order.status)),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _pdfCell(
    String text, {
    bool header = false,
    bool ltr = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: pw.Text(
        text.isEmpty ? '-' : text,
        textDirection: ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
        textAlign: header ? pw.TextAlign.center : pw.TextAlign.right,
        style: pw.TextStyle(
          color: header ? pdf.PdfColors.white : pdf.PdfColors.black,
          fontSize: header ? 9 : 8,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static int _count(List<Order> orders, OrderStatus status) =>
      orders.where((order) => order.status == status).length;

  static double _totalCod(List<Order> orders) =>
      orders.fold<double>(0, (total, order) => total + order.cod);

  static String _statusAr(OrderStatus status) => switch (status) {
    OrderStatus.sent => 'مرسل',
    OrderStatus.delivered => 'تم التسليم',
    OrderStatus.returned => 'مرتجع',
  };

  static String _dateAr(DateTime date) =>
      DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(date);

  static String _fileStamp() =>
      DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  static Future<void> _share(
    BuildContext context,
    File file,
    String title,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        title: title,
        files: [XFile(file.path)],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }
}

class ReportRow extends StatelessWidget {
  const ReportRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}

class StatusReportBar extends StatelessWidget {
  const StatusReportBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
    super.key,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label)),
                Text('$count'),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: count / total,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(CupertinoIcons.doc_text_search, size: 42),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
