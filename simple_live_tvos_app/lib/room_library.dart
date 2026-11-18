import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'site_registry.dart';

class RoomLibrary extends ChangeNotifier {
  RoomLibrary._();
  static final instance = RoomLibrary._();
  static const _favoritesKey = 'tvos_favorites_v1';
  static const _recentKey = 'tvos_recent_v1';
  static const _danmakuKey = 'tvos_danmaku_enabled_v1';
  SharedPreferences? _prefs;
  List<RoomRef> favorites = [];
  List<RoomRef> recent = [];
  bool danmakuEnabled = true;
  String? persistenceWarning;

  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      favorites = _decode(_prefs?.getString(_favoritesKey));
      recent = _decode(_prefs?.getString(_recentKey));
      danmakuEnabled = _prefs?.getBool(_danmakuKey) ?? true;
    } catch (e) {
      // Do not crash the TV app if the tvOS preferences plugin fails.
      persistenceWarning = '本地存储不可用，当前记录只在本次运行保留：$e';
    }
    notifyListeners();
  }

  List<RoomRef> _decode(String? value) {
    if (value == null || value.isEmpty) return [];
    try {
      final data = jsonDecode(value);
      if (data is! List) return [];
      return data.map(RoomRef.fromJson).whereType<RoomRef>().toList();
    } catch (_) {
      return [];
    }
  }

  bool isFavorite(RoomRef room) => favorites.any((r) => r.key == room.key);

  Future<void> toggleFavorite(RoomRef room) async {
    if (isFavorite(room)) {
      favorites = favorites.where((r) => r.key != room.key).toList();
    } else {
      favorites = [room, ...favorites].take(200).toList();
    }
    notifyListeners();
    await _store(_favoritesKey, favorites);
  }

  Future<void> visited(RoomRef room) async {
    recent = [
      room,
      ...recent.where((r) => r.key != room.key),
    ].take(80).toList();
    notifyListeners();
    await _store(_recentKey, recent);
  }

  Future<void> setDanmaku(bool enabled) async {
    danmakuEnabled = enabled;
    notifyListeners();
    try {
      await _prefs?.setBool(_danmakuKey, enabled);
    } catch (e) {
      persistenceWarning = '弹幕设置未能持久化：$e';
      notifyListeners();
    }
  }

  Future<void> clearRecent() async {
    recent = [];
    notifyListeners();
    await _store(_recentKey, recent);
  }

  Future<void> _store(String key, List<RoomRef> values) async {
    try {
      await _prefs?.setString(
        key,
        jsonEncode(values.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      persistenceWarning = '本地记录未能持久化：$e';
      notifyListeners();
    }
  }
}
