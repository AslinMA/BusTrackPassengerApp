import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/passenger.dart';

class LoginService {
  static const _keyPassenger = 'saved_passenger';

  static Future<void> savePassenger(Passenger passenger) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPassenger, jsonEncode(passenger.toJson()));
  }

  static Future<Passenger?> getPassenger() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPassenger);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return Passenger.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearPassenger() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPassenger);
  }
}
