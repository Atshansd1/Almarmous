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
    this.rawText = '',
    this.labelImagePath = '',
    this.timeline = const [],
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
  final String rawText;
  final String labelImagePath;
  final List<String> timeline;

  Order copyWith({
    String? trackingNumber,
    String? phone,
    String? city,
    String? area,
    double? cod,
    OrderStatus? status,
    String? rawText,
    String? labelImagePath,
    List<String>? timeline,
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
      rawText: rawText ?? this.rawText,
      labelImagePath: labelImagePath ?? this.labelImagePath,
      timeline: timeline ?? nextTimeline,
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
    'rawText': rawText,
    'labelImagePath': labelImagePath,
    'timeline': timeline,
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
      rawText: json['rawText'] as String? ?? '',
      labelImagePath: json['labelImagePath'] as String? ?? '',
      timeline: (json['timeline'] as List?)?.cast<String>() ?? const [],
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
  static const _collection = 'orders';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final List<Order> _orders = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSubscription;
  StreamSubscription<User?>? _authSubscription;
  User? _user;
  bool _loaded = false;
  bool _migrationStarted = false;

  OrderStore() {
    if (Platform.isAndroid || Platform.isIOS) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        _user = user;
        if (user == null) {
          _ordersSubscription?.cancel();
          _ordersSubscription = null;
          return;
        }
        _startCloudSync();
        unawaited(NotificationService.configure(user));
      });
    }
  }

  List<Order> get orders {
    final copy = [..._orders];
    copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }

  bool get loaded => _loaded;

  Future<void> load() async {
    final encoded = await _prefs.getString(_storageKey);
    if (encoded != null) {
      final values = (jsonDecode(encoded) as List).map(
        (item) => Map<String, Object?>.from(item as Map),
      );
      _orders
        ..clear()
        ..addAll(values.map(Order.fromJson));
    }
    _loaded = true;
    if (Platform.isAndroid || Platform.isIOS) {
      _user = FirebaseAuth.instance.currentUser;
      if (_user != null) _startCloudSync();
    }
    notifyListeners();
  }

  Future<void> saveOrder(Order order) async {
    _upsertLocal(order);
    await _persist();
    if (_user != null && (Platform.isAndroid || Platform.isIOS)) {
      await _cloudOrders.doc(order.id).set({
        ...order.toJson(),
        'updatedBy': _user!.uid,
        'updatedByEmail': _user!.email,
        'syncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void _upsertLocal(Order order) {
    final index = _orders.indexWhere((item) => item.id == order.id);
    if (index == -1) {
      _orders.add(order);
    } else {
      _orders[index] = order;
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

  Future<void> removeOrder(String id) async {
    _orders.removeWhere((order) => order.id == id);
    await _persist();
    if (_user != null && (Platform.isAndroid || Platform.isIOS)) {
      await _cloudOrders.doc(id).delete();
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _storageKey,
      jsonEncode(_orders.map((order) => order.toJson()).toList()),
    );
    notifyListeners();
  }

  CollectionReference<Map<String, dynamic>> get _cloudOrders =>
      FirebaseFirestore.instance.collection(_collection);

  void _startCloudSync() {
    if (_ordersSubscription != null) return;
    if (!_migrationStarted && _orders.isNotEmpty) {
      _migrationStarted = true;
      unawaited(_migrateLocalOrders());
    }
    _ordersSubscription = _cloudOrders
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) async {
            final cloudOrders = snapshot.docs.map((doc) {
              final data = doc.data();
              return Order.fromJson({...data, 'id': data['id'] ?? doc.id});
            }).toList();
            _orders
              ..clear()
              ..addAll(cloudOrders);
            _loaded = true;
            await _persist();
          },
          onError: (_) {
            _loaded = true;
            notifyListeners();
          },
        );
  }

  Future<void> _migrateLocalOrders() async {
    final user = _user;
    if (user == null) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final order in _orders) {
      batch.set(_cloudOrders.doc(order.id), {
        ...order.toJson(),
        'updatedBy': user.uid,
        'updatedByEmail': user.email,
        'syncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  @override
  void dispose() {
    unawaited(_ordersSubscription?.cancel());
    unawaited(_authSubscription?.cancel());
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
  const ParsedOrderData({
    required this.trackingNumber,
    required this.phone,
    required this.city,
    required this.area,
    required this.cod,
    required this.rawText,
    this.labelImagePath = '',
  });

  final String trackingNumber;
  final String phone;
  final String city;
  final String area;
  final double cod;
  final String rawText;
  final String labelImagePath;

  ParsedOrderData copyWith({String? trackingNumber, String? labelImagePath}) {
    return ParsedOrderData(
      trackingNumber: trackingNumber ?? this.trackingNumber,
      phone: phone,
      city: city,
      area: area,
      cod: cod,
      rawText: rawText,
      labelImagePath: labelImagePath ?? this.labelImagePath,
    );
  }
}

class LabelParser {
  static ParsedOrderData parse(String text) {
    final normalized = _normalizeDigits(text);
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
      rawText: text,
    );
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
    final phonePattern = RegExp(r'(?:\+?971[\s-]?|0)?5\d(?:[\s-]?\d){7,8}');
    for (final source in [...lines, compact]) {
      for (final match in phonePattern.allMatches(source)) {
        final value = _normalizePhone(
          match.group(0)!.replaceAll(RegExp(r'[\s-]'), ''),
        );
        if (!_isSupportNumber(value) && !_belongsTo(value, tracking)) {
          return value;
        }
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
      'اجمالي الاستلام',
      'إجمالي الاستلام',
      'الاستلام',
    ];

    for (var i = 0; i < lines.length; i++) {
      if (!_containsAny(lines[i], labels)) continue;
      final nearby = lines.skip(i).take(4).join(' ');
      final value = _firstMoneyValue(nearby, tracking, phone);
      if (value > 0) return value;
    }

    final compactValue = _firstMoneyValue(compact, tracking, phone);
    if (compactValue > 0) return compactValue;

    final values = _moneyMatches(compact, tracking, phone).toList();
    return values.isEmpty ? 0 : values.first;
  }

  static double _firstMoneyValue(String text, String tracking, String phone) {
    final values = _moneyMatches(text, tracking, phone).toList();
    return values.isEmpty ? 0 : values.first;
  }

  static Iterable<double> _moneyMatches(
    String text,
    String tracking,
    String phone,
  ) sync* {
    final searchable = text.replaceAll(RegExp(r'600\s*500\s*555'), ' ');
    for (final match in RegExp(
      r'\b\d{1,4}(?:[.,]\d{1,2})?\b',
    ).allMatches(searchable)) {
      final raw = match.group(0)!;
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
    for (final rawLine in lines) {
      final line = _cleanField(rawLine, const []);
      if (!_hasArabic(line)) continue;
      for (final city in _knownCities) {
        final index = line.indexOf(city);
        if (index < 0) continue;
        final before = line.substring(0, index).trim();
        final after = line.substring(index + city.length).trim();
        final area = _cleanArea(
          [before, after]
              .where((part) => part.isNotEmpty)
              .join(' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
        );
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
    var area = value
        .replaceAll('شارع الجلاد', 'شارع الإعلام')
        .replaceAll('شارع الجلال', 'شارع الإعلام')
        .replaceAll('شارع الاعلام', 'شارع الإعلام')
        .replaceAll('شارع الإعلام', 'شارع الإعلام')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final streetIndex = area.indexOf('شارع');
    if (streetIndex > 0 &&
        ['المي', 'المية', 'المي الي', 'الميه'].any(area.startsWith)) {
      area = area.substring(streetIndex).trim();
    }

    return area;
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
    return owner
        .replaceAll(RegExp(r'\D'), '')
        .contains(value.replaceAll(RegExp(r'\D'), ''));
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
      'site': 'almarmous.ae',
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
      'scan': 'مسح',
      'scanLabel': 'مسح الملصق',
      'fromCamera': 'الكاميرا',
      'fromGallery': 'المعرض',
      'manualOrder': 'إضافة يدوي',
      'barcode': 'باركود',
      'scanBarcode': 'مسح الباركود',
      'scannerStarting': 'جاري تشغيل الماسح...',
      'scannerError': 'تعذر فتح ماسح الباركود.',
      'quickActions': 'إجراءات سريعة',
      'all': 'الكل',
      'totalOrders': 'كل الطلبات',
      'sent': 'مرسل',
      'delivered': 'تم التسليم',
      'returned': 'مرتجع',
      'codTotal': 'إجمالي التحصيل',
      'recentOrders': 'آخر الطلبات',
      'noOrders': 'لا توجد طلبات',
      'startScan': 'امسح ملصق الشحنة أو أضف طلبا يدويا.',
      'tracking': 'رقم التتبع',
      'phone': 'رقم المستلم',
      'city': 'المدينة',
      'area': 'المنطقة',
      'cod': 'إجمالي التحصيل',
      'status': 'الحالة',
      'date': 'التاريخ',
      'save': 'حفظ',
      'delete': 'حذف',
      'search': 'بحث في الطلبات',
      'language': 'اللغة',
      'english': 'English',
      'arabic': 'العربية',
      'ocrFailed': 'تعذر قراءة الملصق. جرب صورة أوضح.',
      'extracted': 'تم الاستخراج من الملصق',
      'reportSummary': 'ملخص الحالات',
      'today': 'اليوم',
      'thisWeek': 'هذا الأسبوع',
      'editOrder': 'تعديل الطلب',
      'exportPdf': 'تصدير PDF',
      'exportExcel': 'تصدير Excel',
      'duplicateTitle': 'الطلب موجود مسبقاً',
      'duplicateMessage': 'رقم التتبع محفوظ من قبل.',
      'openExisting': 'فتح الطلب',
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
    return AnimatedBuilder(
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
      floatingActionButton: FloatingActionButton.extended(
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

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
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
            final columns = constraints.maxWidth > 640 ? 4 : 2;
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
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        ReportRow(label: t('totalOrders'), value: '${orders.length}'),
        const SizedBox(height: 12),
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
          child: ListTile(
            leading: const Icon(CupertinoIcons.arrow_down_circle),
            title: Text(t('appUpdate')),
            subtitle: Text(t('appUpdateHint')),
            trailing: const Icon(CupertinoIcons.chevron_forward),
            onTap: () => UpdateService.maybePrompt(context),
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
  late OrderStatus status;

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
    cod = TextEditingController(
      text: ((order?.cod ?? parsed?.cod ?? 0) == 0)
          ? ''
          : '${order?.cod ?? parsed?.cod}',
    );
    status = order?.status ?? OrderStatus.sent;
  }

  @override
  void dispose() {
    tracking.dispose();
    phone.dispose();
    city.dispose();
    area.dispose();
    cod.dispose();
    super.dispose();
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
            _field(t('phone'), phone, TextInputType.phone),
            Row(
              children: [
                Expanded(child: _field(t('city'), city, TextInputType.text)),
                const SizedBox(width: 10),
                Expanded(child: _field(t('area'), area, TextInputType.text)),
              ],
            ),
            _field(t('cod'), cod, TextInputType.number),
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

  String get _imagePath =>
      widget.order?.labelImagePath ?? widget.parsed?.labelImagePath ?? '';

  Widget _field(
    String label,
    TextEditingController controller,
    TextInputType type,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        inputFormatters: type == TextInputType.number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        decoration: InputDecoration(labelText: label),
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
        cod: double.tryParse(cod.text.trim()) ?? 0,
        status: status,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        rawText: widget.parsed?.rawText ?? existing?.rawText ?? '',
        labelImagePath: _imagePath,
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
    final file = await _writePdf(orders);
    await _share(context, file, 'تقرير طلبات المرموس PDF');
  }

  static Future<void> shareExcel(
    BuildContext context,
    List<Order> orders,
  ) async {
    final file = await _writeExcel(orders);
    await _share(context, file, 'تقرير طلبات المرموس Excel');
  }

  static Future<File> _writePdf(List<Order> orders) async {
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
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
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
          pw.SizedBox(height: 12),
          _pdfStatusSummary(orders),
          pw.SizedBox(height: 12),
          _pdfOrdersTable(orders),
        ],
      ),
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/تقرير_طلبات_المرموس_${_fileStamp()}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static Future<File> _writeExcel(List<Order> orders) async {
    final workbook = xlsio.Workbook();
    workbook.isRightToLeft = true;
    final sheet = workbook.worksheets[0];
    sheet.name = 'تقرير الطلبات';
    sheet.isRightToLeft = true;

    sheet.getRangeByName('A1:H1').merge();
    sheet.getRangeByName('A1').setText('تقرير طلبات المرموس');
    sheet.getRangeByName('A1').cellStyle
      ..bold = true
      ..fontSize = 18
      ..fontColor = '#FFFFFF'
      ..backColor = '#171717'
      ..hAlign = xlsio.HAlignType.center;

    sheet.getRangeByName('A2:H2').merge();
    sheet
        .getRangeByName('A2')
        .setText(
          'تاريخ التقرير: ${DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(DateTime.now())}',
        );
    sheet.getRangeByName('A2').cellStyle
      ..hAlign = xlsio.HAlignType.center
      ..fontColor = '#6B6257';

    sheet.getRangeByName('A4').setText('إجمالي الطلبات');
    sheet.getRangeByName('B4').setNumber(orders.length.toDouble());
    sheet.getRangeByName('C4').setText('إجمالي التحصيل');
    sheet.getRangeByName('D4').setNumber(_totalCod(orders));
    sheet.getRangeByName('E4').setText('مرسل');
    sheet
        .getRangeByName('F4')
        .setNumber(_count(orders, OrderStatus.sent).toDouble());
    sheet.getRangeByName('G4').setText('تم التسليم');
    sheet
        .getRangeByName('H4')
        .setNumber(_count(orders, OrderStatus.delivered).toDouble());
    sheet.getRangeByName('A4:H4').cellStyle
      ..bold = true
      ..backColor = '#F6E5B8'
      ..hAlign = xlsio.HAlignType.center;

    final headers = const [
      'رقم التتبع',
      'رقم المستلم',
      'المدينة',
      'المنطقة',
      'إجمالي التحصيل',
      'الحالة',
      'تاريخ الإنشاء',
      'آخر تحديث',
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
    for (var row = 0; row < orders.length; row++) {
      final order = orders[row];
      final index = row + 7;
      sheet.getRangeByIndex(index, 1).setText(order.trackingNumber);
      sheet.getRangeByIndex(index, 2).setText(order.phone);
      sheet.getRangeByIndex(index, 3).setText(order.city);
      sheet.getRangeByIndex(index, 4).setText(order.area);
      sheet.getRangeByIndex(index, 5).setNumber(order.cod);
      sheet.getRangeByIndex(index, 6).setText(_statusAr(order.status));
      sheet.getRangeByIndex(index, 7).setText(_dateAr(order.createdAt));
      sheet.getRangeByIndex(index, 8).setText(_dateAr(order.updatedAt));
      sheet.getRangeByIndex(index, 1, index, 8).cellStyle
        ..hAlign = xlsio.HAlignType.right
        ..fontName = 'Arial'
        ..fontSize = 12;
    }
    for (var i = 1; i <= headers.length; i++) {
      sheet.autoFitColumn(i);
    }
    sheet.getRangeByName('E7:E${orders.length + 7}').cellStyle.numberFormat =
        '#,##0.00 "درهم"';
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/تقرير_طلبات_المرموس_${_fileStamp()}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
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

  static pw.Widget _pdfOrdersTable(List<Order> orders) {
    final headers = const [
      'رقم التتبع',
      'رقم المستلم',
      'المدينة',
      'المنطقة',
      'التحصيل',
      'الحالة',
      'التاريخ',
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: pdf.PdfColor.fromHex('#E4D7BC')),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.5),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1),
        4: pw.FlexColumnWidth(1),
        5: pw.FlexColumnWidth(1),
        6: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: pdf.PdfColor.fromHex('#806109')),
          children: headers
              .map((text) => _pdfCell(text, header: true))
              .toList(),
        ),
        ...orders.map(
          (order) => pw.TableRow(
            children: [
              _pdfCell(order.trackingNumber),
              _pdfCell(order.phone, ltr: true),
              _pdfCell(order.city),
              _pdfCell(order.area),
              _pdfCell('${order.cod.toStringAsFixed(2)} درهم'),
              _pdfCell(_statusAr(order.status)),
              _pdfCell(_dateAr(order.createdAt)),
            ],
          ),
        ),
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
