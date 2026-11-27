import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const blush = Color(0xFFFFF5F6);
const red = Color(0xFFC8102E);
const activeRed = Color(0xFFE31837);
const heading = Color(0xFF8B001B);
const pink = Color(0xFFF4A6B5);
const palePink = Color(0xFFFCE4E8);
const ink = Color(0xFF6B5960);
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const defaultCategories = ['Sarees', 'Shirts', 'Shoe', 'Accessories'];

void main() => runApp(const WishWalletApp());

class Wish {
  Wish({
    required this.id,
    required this.name,
    required this.url,
    required this.category,
    this.price,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String url;
  final String category;
  final double? price;
  final String? imageUrl;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'category': category,
    'price': price,
    'imageUrl': imageUrl,
  };

  factory Wish.fromJson(Map<String, dynamic> json) => Wish(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    category: json['category'] as String,
    price: (json['price'] as num?)?.toDouble(),
    imageUrl: json['imageUrl'] as String?,
  );
}

class WishWalletApp extends StatefulWidget {
  const WishWalletApp({super.key});

  @override
  State<WishWalletApp> createState() => _WishWalletAppState();
}

class _WishWalletAppState extends State<WishWalletApp> {
  bool _ready = false;
  bool _signedIn = false;
  String _userId = '';
  String? _pendingRecoveryCode;
  String _serverToken = '';
  String? _serverError;
  final Map<String, int> _serverCategoryIds = {};
  List<String> _categories = List.of(defaultCategories);
  List<Wish> _wishes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? '';
    final serverToken = prefs.getString('serverToken') ?? '';
    final signedIn =
        (prefs.getBool('signedIn') ?? false) &&
        (apiBaseUrl.isEmpty || serverToken.isNotEmpty);
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _serverToken = serverToken;
      _signedIn = signedIn;
      _ready = true;
    });
    if (signedIn && apiBaseUrl.isEmpty) {
      await _loadLocalData(userId, migrateLegacy: true);
    } else if (signedIn) {
      try {
        await _loadServerData();
      } on Exception catch (error) {
        if (mounted) setState(() => _serverError = error.toString());
      }
    }
    await _save();
  }

  String _accountKey(String key, String userId) =>
      '${key}_${base64Url.encode(utf8.encode(userId))}';

  Future<void> _loadLocalData(
    String userId, {
    bool migrateLegacy = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var categories = prefs.getStringList(_accountKey('categories', userId));
    var savedWishes = prefs.getString(_accountKey('wishes', userId));
    if (migrateLegacy && (categories == null || savedWishes == null)) {
      categories ??= prefs.getStringList('categories');
      savedWishes ??= prefs.getString('wishes');
    }
    categories ??= userId == 'demo' ? List.of(defaultCategories) : <String>[];
    final wishes = savedWishes == null
        ? userId == 'demo'
              ? _sampleWishes
              : <Wish>[]
        : (jsonDecode(savedWishes) as List<dynamic>)
              .map((item) => Wish.fromJson(item as Map<String, dynamic>))
              .toList();
    if (!mounted) return;
    setState(() {
      _categories = categories!;
      _wishes = wishes;
    });
    await prefs.setStringList(_accountKey('categories', userId), categories);
    await prefs.setString(
      _accountKey('wishes', userId),
      jsonEncode(wishes.map((wish) => wish.toJson()).toList()),
    );
  }

  List<Wish> get _sampleWishes => [
    Wish(
      id: '1',
      name: 'Red Checkered Saree',
      url: '',
      category: 'Sarees',
      price: 1200,
    ),
    Wish(
      id: '2',
      name: 'White Floral Kurti',
      url: '',
      category: 'Sarees',
      price: 700,
    ),
    Wish(id: '3', name: 'White Shirt', url: '', category: 'Shirts', price: 250),
    Wish(id: '4', name: 'Comet Chinos', url: '', category: 'Shoe', price: 250),
  ];

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_userId.isNotEmpty && apiBaseUrl.isEmpty) {
      await prefs.setStringList(
        _accountKey('categories', _userId),
        _categories,
      );
      await prefs.setString(
        _accountKey('wishes', _userId),
        jsonEncode(_wishes.map((wish) => wish.toJson()).toList()),
      );
    }
    await prefs.setString('userId', _userId);
    await prefs.setString('serverToken', _serverToken);
    await prefs.setBool('signedIn', _signedIn);
  }

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_serverToken',
  };

  String _apiError(http.Response response) {
    try {
      final detail =
          (jsonDecode(response.body) as Map<String, dynamic>)['detail'];
      return detail?.toString() ?? 'Request failed (${response.statusCode}).';
    } on FormatException {
      return 'Request failed (${response.statusCode}).';
    }
  }

  Future<void> _loadServerData() async {
    final response = await http
        .get(Uri.parse('$apiBaseUrl/api/categories'), headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception(_apiError(response));
    final rows = jsonDecode(response.body) as List<dynamic>;
    final categories = <String>[];
    final wishes = <Wish>[];
    _serverCategoryIds.clear();
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final name = row['name'] as String;
      final categoryId = row['id'] as int;
      categories.add(name);
      _serverCategoryIds[name] = categoryId;
      for (final item in (row['wishes'] as List<dynamic>)) {
        final wish = item as Map<String, dynamic>;
        wishes.add(
          Wish(
            id: '${wish['id']}',
            name: wish['name'] as String,
            url: wish['url'] as String,
            category: name,
            price: (wish['price'] as num?)?.toDouble(),
            imageUrl: wish['image_url'] as String?,
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _wishes = wishes;
      _serverError = null;
    });
    await _save();
  }

  Future<bool> _register(String userId, String password) async {
    final recoveryCode = _generateRecoveryCode();
    if (apiBaseUrl.isNotEmpty) {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'password': password,
              'recovery_code': recoveryCode,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 201) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _serverToken = data['access_token'] as String;
      _userId = userId;
      _pendingRecoveryCode = recoveryCode;
      _signedIn = true;
      setState(() {});
      try {
        await _loadServerData();
      } on Exception catch (error) {
        _serverError = error.toString();
        setState(() {});
      }
      await _save();
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    final accounts = _readLocalAccounts(prefs);
    if (accounts.containsKey(userId) ||
        (prefs.getString('userId') == userId &&
            prefs.containsKey('passwordHash'))) {
      return false;
    }
    accounts[userId] = _passwordDigest(userId, password);
    await prefs.setString('localAccounts', jsonEncode(accounts));
    final recoveryCodes = _readLocalRecoveryCodes(prefs)
      ..[userId] = _recoveryDigest(recoveryCode);
    await prefs.setString('localRecoveryCodes', jsonEncode(recoveryCodes));
    await prefs.setString('userId', userId);
    setState(() {
      _userId = userId;
      _pendingRecoveryCode = recoveryCode;
      _signedIn = true;
    });
    await _loadLocalData(userId);
    await _save();
    return true;
  }

  Map<String, String> _readLocalAccounts(SharedPreferences prefs) {
    final encoded = prefs.getString('localAccounts');
    if (encoded == null) return {};
    return (jsonDecode(encoded) as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    );
  }

  Map<String, String> _readLocalRecoveryCodes(SharedPreferences prefs) {
    final encoded = prefs.getString('localRecoveryCodes');
    if (encoded == null) return {};
    return (jsonDecode(encoded) as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    );
  }

  String _passwordDigest(String userId, String password) =>
      sha256.convert(utf8.encode('$userId:$password')).toString();

  String _recoveryDigest(String recoveryCode) =>
      sha256.convert(utf8.encode(recoveryCode.trim().toUpperCase())).toString();

  String _generateRecoveryCode() {
    final random = math.Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join().toUpperCase();
  }

  Future<bool> _login(String userId, String password) async {
    if (apiBaseUrl.isNotEmpty) {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _serverToken = data['access_token'] as String;
      _userId = userId;
      _pendingRecoveryCode = data['recovery_code'] as String?;
      _signedIn = true;
      setState(() {});
      try {
        await _loadServerData();
      } on Exception catch (error) {
        _serverError = error.toString();
        setState(() {});
      }
      await _save();
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    final accounts = _readLocalAccounts(prefs);
    final savedHash =
        accounts[userId] ??
        (prefs.getString('userId') == userId
            ? prefs.getString('passwordHash')
            : null);
    if (savedHash != _passwordDigest(userId, password)) {
      return false;
    }
    accounts[userId] = savedHash!;
    await prefs.setString('localAccounts', jsonEncode(accounts));
    final recoveryCodes = _readLocalRecoveryCodes(prefs);
    final recoveryCode = recoveryCodes.containsKey(userId)
        ? null
        : _generateRecoveryCode();
    if (recoveryCode != null) {
      recoveryCodes[userId] = _recoveryDigest(recoveryCode);
      await prefs.setString('localRecoveryCodes', jsonEncode(recoveryCodes));
    }
    setState(() {
      _userId = userId;
      _pendingRecoveryCode = recoveryCode;
      _signedIn = true;
    });
    await _loadLocalData(userId, migrateLegacy: true);
    await _save();
    return true;
  }

  Future<void> _enterDemoAccount() async {
    if (apiBaseUrl.isNotEmpty) {
      throw StateError('The demo account is available in offline mode.');
    }
    final prefs = await SharedPreferences.getInstance();
    final accounts = _readLocalAccounts(prefs);
    accounts.putIfAbsent('demo', () => _passwordDigest('demo', 'Demo1234'));
    await prefs.setString('localAccounts', jsonEncode(accounts));
    setState(() {
      _userId = 'demo';
      _pendingRecoveryCode = null;
      _serverToken = '';
      _signedIn = true;
    });
    await _loadLocalData('demo');
    await _save();
  }

  Future<String?> _resetPassword(
    String userId,
    String recoveryCode,
    String password,
  ) async {
    final newRecoveryCode = _generateRecoveryCode();
    if (apiBaseUrl.isNotEmpty) {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/auth/recover-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'recovery_code': recoveryCode,
              'new_recovery_code': newRecoveryCode,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200 ? newRecoveryCode : null;
    }
    final prefs = await SharedPreferences.getInstance();
    final accounts = _readLocalAccounts(prefs);
    if (!accounts.containsKey(userId) &&
        prefs.getString('userId') == userId &&
        prefs.containsKey('passwordHash')) {
      accounts[userId] = prefs.getString('passwordHash')!;
    }
    final recoveryCodes = _readLocalRecoveryCodes(prefs);
    if (!accounts.containsKey(userId) ||
        recoveryCodes[userId] != _recoveryDigest(recoveryCode)) {
      return null;
    }
    accounts[userId] = _passwordDigest(userId, password);
    await prefs.setString('localAccounts', jsonEncode(accounts));
    recoveryCodes[userId] = _recoveryDigest(newRecoveryCode);
    await prefs.setString('localRecoveryCodes', jsonEncode(recoveryCodes));
    return newRecoveryCode;
  }

  Future<void> _deleteAccount() async {
    final userId = _userId;
    if (userId.isEmpty) throw StateError('No account is currently signed in.');
    if (apiBaseUrl.isNotEmpty) {
      final response = await http
          .delete(
            Uri.parse('$apiBaseUrl/api/auth/account'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 204) throw Exception(_apiError(response));
    } else {
      final prefs = await SharedPreferences.getInstance();
      final accounts = _readLocalAccounts(prefs)..remove(userId);
      await prefs.setString('localAccounts', jsonEncode(accounts));
      final recoveryCodes = _readLocalRecoveryCodes(prefs)..remove(userId);
      await prefs.setString('localRecoveryCodes', jsonEncode(recoveryCodes));
      await prefs.remove(_accountKey('categories', userId));
      await prefs.remove(_accountKey('wishes', userId));
      if (prefs.getString('userId') == userId) {
        await prefs.remove('passwordHash');
        await prefs.remove('categories');
        await prefs.remove('wishes');
      }
    }
    if (!mounted) return;
    setState(() {
      _userId = '';
      _pendingRecoveryCode = null;
      _serverToken = '';
      _signedIn = false;
      _categories = [];
      _wishes = [];
      _serverError = null;
      _serverCategoryIds.clear();
    });
    await _save();
  }

  Future<bool> _changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    if (newPassword.length < 8 ||
        !RegExp(r'[A-Za-z]').hasMatch(newPassword) ||
        !RegExp(r'\d').hasMatch(newPassword)) {
      return false;
    }
    if (apiBaseUrl.isNotEmpty) {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/auth/reset-password'),
            headers: _authHeaders,
            body: jsonEncode({
              'user_id': _userId,
              'current_password': currentPassword,
              'password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return false;
      return true;
    }

    final prefs = await SharedPreferences.getInstance();
    final accounts = _readLocalAccounts(prefs);
    if (accounts[_userId] != _passwordDigest(_userId, currentPassword)) {
      return false;
    }
    accounts[_userId] = _passwordDigest(_userId, newPassword);
    await prefs.setString('localAccounts', jsonEncode(accounts));
    return true;
  }

  Future<bool> _changeUserId(String newUserId, String currentPassword) async {
    final trimmedUserId = newUserId.trim();
    if (trimmedUserId.isEmpty || trimmedUserId.length > 80) return false;
    if (apiBaseUrl.isNotEmpty) {
      final response = await http
          .put(
            Uri.parse('$apiBaseUrl/api/auth/user-id'),
            headers: _authHeaders,
            body: jsonEncode({
              'user_id': trimmedUserId,
              'current_password': currentPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return false;
    } else {
      final prefs = await SharedPreferences.getInstance();
      final accounts = _readLocalAccounts(prefs);
      final oldUserId = _userId;
      final savedHash = accounts[oldUserId];
      if (savedHash == null ||
          savedHash != _passwordDigest(oldUserId, currentPassword)) {
        return false;
      }
      if (trimmedUserId != oldUserId && accounts.containsKey(trimmedUserId)) {
        return false;
      }
      accounts.remove(oldUserId);
      accounts[trimmedUserId] = _passwordDigest(trimmedUserId, currentPassword);
      final categories = prefs.getStringList(
        _accountKey('categories', oldUserId),
      );
      final wishes = prefs.getString(_accountKey('wishes', oldUserId));
      final recoveryCodes = _readLocalRecoveryCodes(prefs);
      final recoveryCodeHash = recoveryCodes.remove(oldUserId);
      if (recoveryCodeHash != null) {
        recoveryCodes[trimmedUserId] = recoveryCodeHash;
      }
      await prefs.setString('localAccounts', jsonEncode(accounts));
      await prefs.setString('localRecoveryCodes', jsonEncode(recoveryCodes));
      if (categories != null) {
        await prefs.setStringList(
          _accountKey('categories', trimmedUserId),
          categories,
        );
      }
      if (wishes != null) {
        await prefs.setString(_accountKey('wishes', trimmedUserId), wishes);
      }
      await prefs.remove(_accountKey('categories', oldUserId));
      await prefs.remove(_accountKey('wishes', oldUserId));
    }
    if (!mounted) return false;
    setState(() => _userId = trimmedUserId);
    await _save();
    return true;
  }

  Future<void> _addWish(Wish wish) async {
    var savedWish = wish;
    if (apiBaseUrl.isNotEmpty) {
      final categoryId = _serverCategoryIds[wish.category];
      if (categoryId == null) {
        throw StateError('The selected category is unavailable.');
      }
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/wishes'),
            headers: _authHeaders,
            body: jsonEncode({
              'name': wish.name,
              'url': wish.url,
              'category_id': categoryId,
              'price': wish.price,
              'image_url': wish.imageUrl,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 201) throw Exception(_apiError(response));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      savedWish = Wish(
        id: '${data['id']}',
        name: data['name'] as String,
        url: data['url'] as String,
        category: wish.category,
        price: (data['price'] as num?)?.toDouble(),
        imageUrl: data['image_url'] as String?,
      );
    }
    setState(() => _wishes = [..._wishes, savedWish]);
    await _save();
  }

  Future<void> _removeWish(Wish wish) async {
    if (apiBaseUrl.isNotEmpty) {
      final wishId = int.tryParse(wish.id);
      if (wishId == null) throw StateError('The selected wish is unavailable.');
      final response = await http
          .delete(
            Uri.parse('$apiBaseUrl/api/wishes/$wishId'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 204) throw Exception(_apiError(response));
    }
    setState(() => _wishes.removeWhere((item) => item.id == wish.id));
    await _save();
  }

  Future<void> _addCategory(String name) async {
    if (apiBaseUrl.isNotEmpty) {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/categories'),
            headers: _authHeaders,
            body: jsonEncode({'name': name}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 201) throw Exception(_apiError(response));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _serverCategoryIds[name] = data['id'] as int;
    }
    setState(() => _categories = [..._categories, name]);
    await _save();
  }

  Future<void> _removeCategory(String category) async {
    if (apiBaseUrl.isNotEmpty) {
      final categoryId = _serverCategoryIds[category];
      if (categoryId == null) {
        throw StateError('The selected category is unavailable.');
      }
      final response = await http
          .delete(
            Uri.parse('$apiBaseUrl/api/categories/$categoryId'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 204) throw Exception(_apiError(response));
      _serverCategoryIds.remove(category);
    }
    setState(() {
      _categories.remove(category);
      _wishes.removeWhere((wish) => wish.category == category);
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WishWallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: blush,
        colorScheme: ColorScheme.fromSeed(
          seedColor: red,
          primary: red,
          secondary: pink,
          surface: Colors.white,
        ),
        fontFamily: GoogleFonts.inter().fontFamily,
        textTheme: GoogleFonts.interTextTheme().copyWith(
          headlineSmall: GoogleFonts.poppins(
            color: heading,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: GoogleFonts.poppins(
            color: heading,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: GoogleFonts.inter(color: ink, fontSize: 13),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: Color(0xFFBFAFB4), fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: palePink),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: palePink),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: pink),
          ),
        ),
      ),
      home: !_ready
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator(color: red)),
            )
          : _signedIn
          ? _HomeShell(
              userId: _userId,
              categories: _categories,
              wishes: _wishes,
              initialRecoveryCode: _pendingRecoveryCode,
              serverToken: _serverToken,
              serverError: _serverError,
              onAddWish: _addWish,
              onRemoveWish: _removeWish,
              onAddCategory: _addCategory,
              onRemoveCategory: _removeCategory,
              onChangePassword: _changePassword,
              onChangeUserId: _changeUserId,
              onDeleteAccount: _deleteAccount,
              onRecoveryCodeShown: () =>
                  setState(() => _pendingRecoveryCode = null),
              onSignOut: () async {
                setState(() => _signedIn = false);
                _serverToken = '';
                await _save();
              },
            )
          : AuthScreen(
              userId: _userId,
              onLogin: _login,
              onRegister: _register,
              onResetPassword: _resetPassword,
              onDemo: _enterDemoAccount,
            ),
    );
  }
}

enum AuthMode { login, signup, reset }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.userId,
    required this.onLogin,
    required this.onRegister,
    required this.onResetPassword,
    required this.onDemo,
    super.key,
  });

  final String userId;
  final Future<bool> Function(String, String) onLogin;
  final Future<bool> Function(String, String) onRegister;
  final Future<String?> Function(String, String, String) onResetPassword;
  final Future<void> Function() onDemo;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode _mode = AuthMode.login;
  final _user = TextEditingController();
  final _recoveryCode = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _user.text = widget.userId;
  }

  @override
  void dispose() {
    _user.dispose();
    _recoveryCode.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _submit() async {
    final userId = _user.text.trim();
    final password = _password.text;
    if (userId.isEmpty || password.isEmpty) {
      _message('Enter your user ID and password.');
      return;
    }
    if (_mode == AuthMode.reset && _recoveryCode.text.trim().isEmpty) {
      _message('Enter your recovery code.');
      return;
    }
    if (_mode != AuthMode.login) {
      if (password.length < 8 ||
          !RegExp(r'[A-Za-z]').hasMatch(password) ||
          !RegExp(r'\d').hasMatch(password)) {
        _message('Use at least 8 characters with a letter and a number.');
        return;
      }
      if (password != _confirm.text) {
        _message('Your passwords do not match.');
        return;
      }
    }
    setState(() => _busy = true);
    var success = false;
    String? newRecoveryCode;
    try {
      if (_mode == AuthMode.login) {
        success = await widget.onLogin(userId, password);
      } else if (_mode == AuthMode.signup) {
        success = await widget.onRegister(userId, password);
      } else {
        newRecoveryCode = await widget.onResetPassword(
          userId,
          _recoveryCode.text,
          password,
        );
        success = newRecoveryCode != null;
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _message('Could not complete the request: $error');
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!success) {
      _message(
        _mode == AuthMode.login
            ? 'Those sign-in details were not recognized.'
            : _mode == AuthMode.signup
            ? 'That user ID already exists. Sign in instead.'
            : 'The user ID or recovery code is incorrect.',
      );
    } else if (_mode == AuthMode.reset) {
      await _showRecoveryCodeDialog(context, newRecoveryCode!);
      if (!mounted) return;
      setState(() => _mode = AuthMode.login);
      _message('Password updated. Sign in with your new password.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final login = _mode == AuthMode.login;
    final signup = _mode == AuthMode.signup;
    final title = login
        ? 'Welcome back!!'
        : signup
        ? 'New to Wishes!!'
        : 'Forgot your pass.';
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -110,
              right: -35,
              child: _bubble(230, const Color(0xFFFCE4E8)),
            ),
            Positioned(
              bottom: -90,
              left: -45,
              child: _bubble(170, const Color(0xFFFDE9EC)),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(13, 30, 13, 24),
              children: [
                _BrandHeader(subtitle: title),
                const SizedBox(height: 27),
                Text(
                  login
                      ? 'LOGIN'
                      : signup
                      ? 'Create an account'
                      : 'Reset password',
                  style: const TextStyle(
                    color: heading,
                    fontSize: 16,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  login
                      ? 'Sign in to see the things you’re wishing for.'
                      : signup
                      ? 'Start saving everything you love in one place.'
                      : 'Use your recovery code to reset your password.',
                  style: const TextStyle(color: ink, fontSize: 12),
                ),
                const SizedBox(height: 20),
                _fieldLabel('USER_ID'),
                TextField(
                  controller: _user,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(
                      Icons.person_outline,
                      size: 18,
                      color: pink,
                    ),
                    hintText: 'Enter your user ID',
                  ),
                ),
                const SizedBox(height: 14),
                if (_mode == AuthMode.reset) ...[
                  _fieldLabel('RECOVERY CODE'),
                  TextField(
                    controller: _recoveryCode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.key_outlined,
                        color: pink,
                        size: 18,
                      ),
                      hintText: 'Enter your one-time recovery code',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _fieldLabel(
                  _mode == AuthMode.reset ? 'NEW PASSWORD' : 'PASSWORD',
                ),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: pink,
                    ),
                    hintText: signup
                        ? 'Create a password'
                        : _mode == AuthMode.reset
                        ? 'New password'
                        : '••••••••',
                  ),
                ),
                if (!login) ...[
                  const SizedBox(height: 14),
                  _fieldLabel('CONFIRM PASSWORD'),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.favorite_border,
                        size: 18,
                        color: pink,
                      ),
                      hintText: 'Re-enter your password',
                    ),
                  ),
                ],
                if (login)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _mode = AuthMode.reset),
                      child: const Text(
                        'Forgot password?  →',
                        style: TextStyle(color: red, fontSize: 11),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 18),
                _PrimaryButton(
                  label: _busy
                      ? 'Please wait…'
                      : login
                      ? 'Login'
                      : signup
                      ? 'Create it'
                      : 'Change Password',
                  onPressed: _busy ? null : _submit,
                ),
                if (login && apiBaseUrl.isEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              await widget.onDemo();
                            } on Exception catch (error) {
                              if (mounted) {
                                _message('Could not open demo: $error');
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Continue with demo account'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: red,
                      side: const BorderSide(color: pink),
                    ),
                  ),
                ],
                const SizedBox(height: 17),
                Center(
                  child: TextButton(
                    onPressed: () => setState(
                      () => _mode = login ? AuthMode.signup : AuthMode.login,
                    ),
                    child: Text(
                      login
                          ? 'Don’t have an account?  Create it'
                          : 'Already have an account?  Login',
                      style: const TextStyle(color: ink, fontSize: 12),
                    ),
                  ),
                ),
                if (_mode == AuthMode.reset) ...[
                  const SizedBox(height: 12),
                  _infoNote(
                    'Your recovery code works once. Save the new code shown after resetting your password.',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showRecoveryCodeDialog(
  BuildContext context,
  String recoveryCode,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Save your recovery code'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Keep this code somewhere private. It is shown only once and is replaced after a password reset.',
        ),
        const SizedBox(height: 16),
        SelectableText(
          recoveryCode,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: heading,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Clipboard.setData(ClipboardData(text: recoveryCode)),
        child: const Text('Copy code'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text("I've saved it"),
      ),
    ],
  ),
);

Widget _bubble(double size, Color color) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
);

Widget _heartMark(double size) => Image.asset(
  'assets/heart_signal.png',
  width: size,
  height: size,
  fit: BoxFit.contain,
);

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.subtitle = 'Wish it. Want it. Win it.'});
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _heartMark(52),
      const SizedBox(width: 14),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WishWallet',
            style: TextStyle(
              color: heading,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
            ),
          ),
          const Text(
            'Wish it. Want it. Win it.',
            style: TextStyle(
              color: ink,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
          Text(subtitle, style: const TextStyle(color: red, fontSize: 14)),
        ],
      ),
    ],
  );
}

Widget _fieldLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(
    text,
    style: const TextStyle(
      color: heading,
      fontSize: 10,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w600,
    ),
  ),
);

Widget _infoNote(String text) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: palePink,
    borderRadius: BorderRadius.circular(14),
  ),
  child: Text(text, style: const TextStyle(color: ink, fontSize: 12)),
);

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: red,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        elevation: 4,
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      child: Text(label),
    ),
  );
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({
    required this.userId,
    required this.categories,
    required this.wishes,
    required this.initialRecoveryCode,
    required this.serverToken,
    required this.serverError,
    required this.onAddWish,
    required this.onRemoveWish,
    required this.onAddCategory,
    required this.onRemoveCategory,
    required this.onChangePassword,
    required this.onChangeUserId,
    required this.onDeleteAccount,
    required this.onRecoveryCodeShown,
    required this.onSignOut,
  });

  final String userId;
  final List<String> categories;
  final List<Wish> wishes;
  final String? initialRecoveryCode;
  final String serverToken;
  final String? serverError;
  final Future<void> Function(Wish) onAddWish;
  final Future<void> Function(Wish) onRemoveWish;
  final Future<void> Function(String) onAddCategory;
  final Future<void> Function(String) onRemoveCategory;
  final Future<bool> Function(String, String) onChangePassword;
  final Future<bool> Function(String, String) onChangeUserId;
  final Future<void> Function() onDeleteAccount;
  final VoidCallback onRecoveryCodeShown;
  final VoidCallback onSignOut;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final recoveryCode = widget.initialRecoveryCode;
      if (recoveryCode == null || !mounted) return;
      await _showRecoveryCodeDialog(context, recoveryCode);
      if (mounted) widget.onRecoveryCodeShown();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: _tab == 0
          ? _Dashboard(
              userId: widget.userId,
              categories: widget.categories,
              wishes: widget.wishes,
              serverToken: widget.serverToken,
              serverError: widget.serverError,
              onAddWish: widget.onAddWish,
              onRemoveWish: widget.onRemoveWish,
              onAddCategory: widget.onAddCategory,
              onRemoveCategory: widget.onRemoveCategory,
              onProfile: () => setState(() => _tab = 1),
            )
          : _Profile(
              userId: widget.userId,
              categoryCount: widget.categories.length,
              wishCount: widget.wishes.length,
              onChangePassword: widget.onChangePassword,
              onChangeUserId: widget.onChangeUserId,
              onDeleteAccount: widget.onDeleteAccount,
              onBack: () => setState(() => _tab = 0),
              onSignOut: widget.onSignOut,
            ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      backgroundColor: Colors.white,
      indicatorColor: palePink,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.favorite_border),
          selectedIcon: Icon(Icons.favorite, color: activeRed),
          label: 'Wishes',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person, color: activeRed),
          label: 'My Profile',
        ),
      ],
    ),
  );
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.userId,
    required this.categories,
    required this.wishes,
    required this.serverToken,
    required this.serverError,
    required this.onAddWish,
    required this.onRemoveWish,
    required this.onAddCategory,
    required this.onRemoveCategory,
    required this.onProfile,
  });

  final String userId;
  final List<String> categories;
  final List<Wish> wishes;
  final String serverToken;
  final String? serverError;
  final Future<void> Function(Wish) onAddWish;
  final Future<void> Function(Wish) onRemoveWish;
  final Future<void> Function(String) onAddCategory;
  final Future<void> Function(String) onRemoveCategory;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final total = wishes.fold<double>(
      0,
      (sum, wish) => sum + (wish.price ?? 0),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Row(
            children: [
              _heartMark(27),
              const SizedBox(width: 5),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WishWallet',
                    style: TextStyle(
                      color: heading,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  Text(
                    'Wish it. Want it. Win it.',
                    style: TextStyle(
                      color: ink,
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                onPressed: onProfile,
                icon: const Icon(Icons.account_circle, color: pink),
                tooltip: 'My profile',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: _smallAction(
                  '＋ Add a new wish',
                  red,
                  Colors.white,
                  () => _showAddWish(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _smallAction(
                  '＋ Create a category',
                  pink,
                  Colors.white,
                  () => _showAddCategory(context),
                ),
              ),
            ],
          ),
        ),
        if (serverError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
            child: _infoNote('API sync issue: $serverError'),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 20),
            children: [
              Text(
                'My Wishes!!!  ♥',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 7),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [red, Color(0xFFA90B28)],
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Wish Value',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₹${_formatPrice(total)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${wishes.length} wishes  •  ${categories.length} categories',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (categories.isEmpty)
                _EmptyState(onAddCategory: () => _showAddCategory(context))
              else
                ...categories.map((category) {
                  final items = wishes
                      .where((wish) => wish.category == category)
                      .toList();
                  return _CategorySection(
                    category: category,
                    items: items,
                    onRemoveWish: onRemoveWish,
                    onDeleteCategory: () => _confirmDelete(context, category),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddWish(BuildContext context) async {
    if (categories.isEmpty) {
      await _showAddCategory(context);
      return;
    }
    final wish = await Navigator.of(context).push<Wish>(
      MaterialPageRoute(
        builder: (_) =>
            AddWishScreen(categories: categories, serverToken: serverToken),
      ),
    );
    if (wish != null) {
      try {
        await onAddWish(wish);
      } on Exception catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save wish: $error')),
          );
        }
      }
    }
  }

  Future<void> _showAddCategory(BuildContext context) async {
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AddCategoryScreen()),
    );
    if (!context.mounted) return;
    if (name != null &&
        !categories.any((item) => item.toLowerCase() == name.toLowerCase())) {
      try {
        await onAddCategory(name);
      } on Exception catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create category: $error')),
          );
        }
      }
    } else if (name != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That category already exists.')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('“$category” and its saved wishes will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await onRemoveCategory(category);
      } on Exception catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete category: $error')),
          );
        }
      }
    }
  }
}

Widget _smallAction(
  String label,
  Color background,
  Color foreground,
  VoidCallback onTap,
) => SizedBox(
  height: 35,
  child: ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
    ),
    child: FittedBox(child: Text(label)),
  ),
);

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.items,
    required this.onRemoveWish,
    required this.onDeleteCategory,
  });
  final String category;
  final List<Wish> items;
  final Future<void> Function(Wish) onRemoveWish;
  final VoidCallback onDeleteCategory;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
    decoration: BoxDecoration(
      color: palePink,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                category,
                style: const TextStyle(
                  color: heading,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              '₹${_formatPrice(items.fold<double>(0, (sum, item) => sum + (item.price ?? 0)))}',
              style: const TextStyle(
                color: red,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            _smallAction('Delete Category', pink, heading, onDeleteCategory),
          ],
        ),
        ...items.map(
          (wish) => _WishCard(wish: wish, onRemove: () => onRemoveWish(wish)),
        ),
      ],
    ),
  );
}

class _WishCard extends StatelessWidget {
  const _WishCard({required this.wish, required this.onRemove});
  final Wish wish;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 5),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        _ProductImage(url: wish.imageUrl, size: 43),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                wish.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: heading,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                wish.url.isEmpty
                    ? 'Saved to your wishlist'
                    : _hostName(wish.url),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ink, fontSize: 8),
              ),
            ],
          ),
        ),
        if (wish.price != null)
          Text(
            '₹${_formatPrice(wish.price!)}',
            style: const TextStyle(
              color: red,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: const Icon(Icons.more_vert, color: ink),
          onSelected: (action) async {
            if (action == 'remove') {
              try {
                await onRemove();
              } on Exception catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not remove wish: $error')),
                  );
                }
              }
            }
            if (action == 'open' && wish.url.isNotEmpty) {
              final uri = Uri.tryParse(wish.url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          },
          itemBuilder: (_) => [
            if (wish.url.isNotEmpty)
              const PopupMenuItem(
                value: 'open',
                child: Text('Open product link'),
              ),
            const PopupMenuItem(value: 'remove', child: Text('Remove wish')),
          ],
        ),
      ],
    ),
  );
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url, required this.size});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: SizedBox(
      width: size,
      height: size,
      child: url == null || url!.isEmpty
          ? Container(
              color: const Color(0xFFFFEEF1),
              child: const Icon(Icons.favorite, color: pink, size: 20),
            )
          : Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFFFFEEF1),
                child: const Icon(Icons.shopping_bag_outlined, color: pink),
              ),
            ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddCategory});
  final VoidCallback onAddCategory;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 45),
    child: Column(
      children: [
        const Icon(Icons.favorite_border, color: pink, size: 38),
        const SizedBox(height: 9),
        const Text('No wishes saved yet', style: TextStyle(color: heading)),
        const SizedBox(height: 10),
        _PrimaryButton(label: 'Create a category', onPressed: onAddCategory),
      ],
    ),
  );
}

class AddWishScreen extends StatefulWidget {
  const AddWishScreen({
    required this.categories,
    required this.serverToken,
    super.key,
  });
  final List<String> categories;
  final String serverToken;

  @override
  State<AddWishScreen> createState() => _AddWishScreenState();
}

class _AddWishScreenState extends State<AddWishScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String? _imageUrl;
  String? _scannedUrl;
  String? _scanError;
  double? _fetchedPrice;
  late String _category = widget.categories.first;
  bool _scanning = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid product URL first.')),
      );
      return;
    }
    if (apiBaseUrl.isEmpty) {
      setState(() {
        _scannedUrl = null;
        _scanError = 'Price lookup needs the WishWallet API. Start the backend and launch Chrome with API_BASE_URL configured.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start the WishWallet API to fetch product prices.'),
        ),
      );
      return;
    }
    setState(() {
      _scanning = true;
      _scannedUrl = null;
      _fetchedPrice = null;
      _imageUrl = null;
      _scanError = null;
      _name.clear();
    });
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/metadata/scan'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.serverToken}',
            },
            body: jsonEncode({'url': uri.toString()}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'The store could not be scanned (${response.statusCode}).',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final price = data['price'];
      if (price is! num || price < 0) {
        throw Exception(
          'This store did not provide a readable price. Try a direct product page link.',
        );
      }
      final scannedName = data['name'] as String? ?? '';
      if (scannedName.isNotEmpty) _name.text = scannedName;
      _imageUrl = data['image_url'] as String?;
      _fetchedPrice = price.toDouble();
      _scannedUrl = uri.toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product name and price fetched.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanError = error.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not scan this link: $error')),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _saveWish() {
    final url = _url.text.trim();
    final parsed = Uri.tryParse(url);
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan the product link first.')),
      );
      return;
    }
    if (parsed == null ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a valid http or https product link.'),
        ),
      );
      return;
    }
    if (_scannedUrl != url || _fetchedPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fetch the product price from its link before saving.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      Wish(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        url: url,
        category: _category,
        price: _fetchedPrice,
        imageUrl: _imageUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: blush,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_ios_new, color: heading, size: 18),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _heartMark(30),
          const SizedBox(width: 8),
          const Text(
            'Add a new Wish',
            style: TextStyle(
              color: heading,
              fontSize: 17,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        _fieldLabel('PRODUCT NAME'),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            prefixIcon: Icon(
              Icons.shopping_bag_outlined,
              color: pink,
              size: 18,
            ),
            hintText: 'e.g. Red Check Saree',
          ),
        ),
        const SizedBox(height: 17),
        _fieldLabel('PRODUCT LINK'),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          onChanged: (_) {
            setState(() {
              _scannedUrl = null;
              _fetchedPrice = null;
              _imageUrl = null;
              _scanError = null;
            });
          },
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.link, color: pink, size: 18),
            hintText: 'https://',
          ),
        ),
        const SizedBox(height: 7),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 16),
            label: Text(
              _scanning ? 'Fetching…' : 'Fetch name and price from link',
            ),
          ),
        ),
        if (_fetchedPrice != null)
          Container(
            margin: const EdgeInsets.only(bottom: 17),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palePink,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: red, size: 19),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Price fetched from product page',
                    style: TextStyle(color: heading, fontSize: 12),
                  ),
                ),
                Text(
                  '₹${_formatPrice(_fetchedPrice!)}',
                  style: const TextStyle(
                    color: red,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
        else if (_scanError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              _scanError!,
              style: const TextStyle(color: red, fontSize: 11),
            ),
          ),
        const SizedBox(height: 17),
        _fieldLabel('CATEGORY'),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.folder_outlined, color: pink),
          ),
          items: widget.categories
              .map(
                (category) =>
                    DropdownMenuItem(value: category, child: Text(category)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _category = value);
          },
        ),
        const SizedBox(height: 34),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 175,
            child: _PrimaryButton(
              label: '♥  Save My Wish',
              onPressed: !_scanning && _scannedUrl == _url.text.trim()
                  ? _saveWish
                  : null,
            ),
          ),
        ),
      ],
    ),
  );
}

class AddCategoryScreen extends StatefulWidget {
  const AddCategoryScreen({super.key});

  @override
  State<AddCategoryScreen> createState() => _AddCategoryScreenState();
}

class _AddCategoryScreenState extends State<AddCategoryScreen> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: blush,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_ios_new, color: heading, size: 18),
      ),
    ),
    body: Stack(
      children: [
        Positioned(
          bottom: -45,
          left: -45,
          child: _bubble(170, const Color(0xFFFDE9EC)),
        ),
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          children: [
            Row(
              children: [
                _heartMark(34),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Wow! Creating a new Category',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: heading,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            _fieldLabel('CATEGORY NAME'),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.folder_open, color: pink, size: 18),
                hintText: 'e.g. Accessories',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Group similar wishes together.',
              style: TextStyle(color: ink, fontSize: 11),
            ),
            const SizedBox(height: 23),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 195,
                child: _PrimaryButton(
                  label: '+  Create my Category',
                  onPressed: () {
                    final name = _name.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a category name.')),
                      );
                    } else {
                      Navigator.pop(context, name);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _EditUserIdDialog extends StatefulWidget {
  const _EditUserIdDialog({required this.userId});

  final String userId;

  @override
  State<_EditUserIdDialog> createState() => _EditUserIdDialogState();
}

class _EditUserIdDialogState extends State<_EditUserIdDialog> {
  late final _userIdController = TextEditingController(text: widget.userId);
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit username'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _userIdController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(hintText: 'New username'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Confirm password'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, (
          _userIdController.text,
          _passwordController.text,
        )),
        child: const Text('Save'),
      ),
    ],
  );
}

class _Profile extends StatelessWidget {
  const _Profile({
    required this.userId,
    required this.categoryCount,
    required this.wishCount,
    required this.onChangePassword,
    required this.onChangeUserId,
    required this.onDeleteAccount,
    required this.onBack,
    required this.onSignOut,
  });
  final String userId;
  final int categoryCount;
  final int wishCount;
  final Future<bool> Function(String, String) onChangePassword;
  final Future<bool> Function(String, String) onChangeUserId;
  final Future<void> Function() onDeleteAccount;
  final VoidCallback onBack;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(14),
    children: [
      Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: heading,
              size: 18,
            ),
          ),
          _heartMark(28),
          const SizedBox(width: 7),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WishWallet',
                style: TextStyle(
                  color: heading,
                  fontSize: 17,
                  fontFamily: 'Poppins',
                ),
              ),
              Text(
                'Wish it. Want it. Win it.',
                style: TextStyle(
                  color: ink,
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [palePink, Color(0xFFFFD6DE)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'My Profile',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: heading,
                            fontSize: 21,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _editUserId(context),
                        icon: const Icon(Icons.edit, size: 12),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: heading,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Manage your account details',
                    style: TextStyle(color: ink, fontSize: 11),
                  ),
                ],
              ),
            ),
            CircleAvatar(
              radius: 31,
              backgroundColor: Colors.white,
              child: Text(
                userId.isEmpty ? '?' : userId[0].toUpperCase(),
                style: const TextStyle(color: pink, fontSize: 25),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('USER ID'),
            InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline, color: pink, size: 17),
              ),
              child: Text(userId, style: const TextStyle(color: ink)),
            ),
            const SizedBox(height: 14),
            _fieldLabel('PASSWORD'),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '••••••••',
                    style: TextStyle(letterSpacing: 3, color: red),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _changePassword(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: heading,
                    side: const BorderSide(color: pink),
                  ),
                  child: const Text('Reset password'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _statCard(Icons.favorite, wishCount, 'Wishes saved')),
          const SizedBox(width: 10),
          Expanded(child: _statCard(Icons.layers, categoryCount, 'Categories')),
        ],
      ),
      const SizedBox(height: 17),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _confirmDeleteAccount(context),
          icon: const Icon(Icons.delete_forever_outlined, size: 17),
          label: const Text('Delete account'),
          style: OutlinedButton.styleFrom(
            foregroundColor: red,
            side: const BorderSide(color: red),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout, size: 17),
          label: const Text('Logout'),
          style: OutlinedButton.styleFrom(
            foregroundColor: red,
            side: const BorderSide(color: red),
          ),
        ),
      ),
    ],
  );

  Future<void> _editUserId(BuildContext context) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _EditUserIdDialog(userId: userId),
    );
    if (result == null || !context.mounted) return;
    try {
      final updated = await onChangeUserId(result.$1, result.$2);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated
                ? 'Username updated.'
                : 'Username is already taken or your password is incorrect.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update username: $error')),
      );
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, categories, and saved wishes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account', style: TextStyle(color: red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await onDeleteAccount();
    } on Exception catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete account: $error')),
      );
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final oldPassword = TextEditingController();
    final newPassword = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPassword,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Current password'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newPassword,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'New password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              '${oldPassword.text}\n${newPassword.text}',
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    final parts = result.split('\n');
    oldPassword.dispose();
    newPassword.dispose();
    try {
      final updated = await onChangePassword(parts[0], parts[1]);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated
                ? 'Password updated.'
                : 'Check your current password and new password requirements.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update password: $error')),
      );
    }
  }
}

Widget _statCard(IconData icon, int value, String label) => Container(
  padding: const EdgeInsets.all(13),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: red, size: 19),
      const SizedBox(height: 5),
      Text(
        '$value',
        style: const TextStyle(
          color: red,
          fontWeight: FontWeight.w800,
          fontSize: 19,
        ),
      ),
      Text(label, style: const TextStyle(color: ink, fontSize: 10)),
    ],
  ),
);

String _hostName(String url) => Uri.tryParse(url)?.host ?? url;

String _formatPrice(double price) => price == price.roundToDouble()
    ? price.toStringAsFixed(0)
    : price.toStringAsFixed(2);
