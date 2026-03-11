import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class ApiService {
  // IMPORTANT: Replace this with your backend URL
  // For local testing: use your computer's IP address
  // For deployed backend: use your Railway/Render URL
  static const String baseUrl = 'https://bustrack-backend-production.up.railway.app/api';



  // If testing on physical phone, use your computer's local IP:
  // static const String baseUrl = 'http://192.168.1.X:3000/api';

  // If backend is deployed:
  // static const String baseUrl = 'https://your-app.railway.app/api';

  // ========== ROUTE METHODS ==========
  Future<Map<String, dynamic>?> createOrUpdatePassenger({
    required String phone,
    required String name,
  }) async {
    final url = Uri.parse('$baseUrl/passengers');
    final payload = {'phone': phone, 'name': name};

    try {
      final response = await http
          .post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      )
          .timeout(const Duration(seconds: 15));

      print('➡️ POST $url');
      print('📤 payload: $payload');
      print('📡 status: ${response.statusCode}');
      print('📦 body: ${response.body}');

      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {'success': false, 'error': 'Invalid response format'};
    } catch (e) {
      print('❌ Exception: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Search for bus routes between two locations
  Future<List<dynamic>> searchRoutes(String from, String to) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/routes/search?from=$from&to=$to'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Failed to load routes: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  /// Get all bus routes
  Future<List<dynamic>> getAllRoutes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/routes'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Failed to load routes');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  /// Get stops for a specific route
  Future<List<dynamic>> getRouteStops(int routeId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/routes/$routeId/stops'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      print('📡 Route stops response: ${response.statusCode}');
      print('📦 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'] ?? data ?? [];
      } else {
        throw Exception('Failed to load stops');
      }
    } catch (e) {
      print('❌ Error loading stops: $e');
      throw Exception('Error loading stops: $e');
    }
  }

  // ========== TRIP/BUS METHODS ==========

  /// Get active trips (buses) on a specific route with live tracking
  Future<List<dynamic>> getBusesOnRoute(int routeId) async {
    try {
      final url = Uri.parse('$baseUrl/trips/active?route_id=$routeId');

      print('📞 Fetching active trips for route: $routeId');

      final response = await http.get(url).timeout(Duration(seconds: 10));

      print('📡 Response: ${response.statusCode}');
      print('📦 Data: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          List<dynamic> trips = data['data'] as List;
          print('✅ Loaded ${trips.length} active trips');
          return trips;
        }
      }

      return []; // Return empty list instead of throwing
    } catch (e) {
      print('❌ Error loading buses: $e');
      return []; // Return empty list on error
    }
  }

  /// Get current location of a specific bus
  Future<Map<String, dynamic>> getBusLocation(int busId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/buses/$busId/location'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get bus location');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  /// Get nearby buses based on current location
  Future<List<dynamic>> getNearbyBuses(
      double lat,
      double lng, {
        int radius = 5000,
      }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/buses/nearby?lat=$lat&lng=$lng&radius=$radius'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'] ?? data['buses'] ?? [];
      } else {
        throw Exception('Failed to load nearby buses');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  /// Get bus capacity and availability
  Future<Map<String, dynamic>> getBusCapacity(int busId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/buses/$busId/capacity'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load capacity');
      }
    } catch (e) {
      throw Exception('Error loading capacity: $e');
    }
  }

  // ========== ETA METHODS ==========

  /// Calculate ETA for a bus to reach a specific stop
  Future<Map<String, dynamic>> calculateETA(int busId, int stopId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/eta/calculate?busId=$busId&stopId=$stopId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to calculate ETA');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ========== BOOKING METHODS ==========

  /// Create a new booking
  Future<Map<String, dynamic>> createBooking({
    required String passengerName,
    required String passengerPhone,
    required int routeId,
    required int busId,
    required int tripId,
    required int pickupStopId,
    int? dropoffStopId,
    required int numberOfPassengers,
    required double fareAmount,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/bookings');

      final body = {
        'passenger_name': passengerName,
        'passenger_phone': passengerPhone,
        'route_id': routeId,
        'bus_id': busId,
        'trip_id': tripId,
        'pickup_stop_id': pickupStopId,
        'dropoff_stop_id': dropoffStopId,
        'number_of_passengers': numberOfPassengers,
        'fare_amount': fareAmount,
        'travel_date': DateTime.now().toIso8601String(),
      };

      print('📤 Creating booking with data: $body');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 15));

      print('📡 Booking API response: ${response.statusCode}');
      print('📦 Response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Booking created successfully');
          return data['data'];
        }
      }

      throw Exception('Failed to create booking: ${response.body}');
    } catch (e) {
      print('❌ Booking API error: $e');
      rethrow;
    }
  }

  /// Get user's bookings by phone number
  Future<List<dynamic>> getUserBookings(String phone) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/bookings/user/$phone'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Failed to load bookings');
      }
    } catch (e) {
      throw Exception('Error loading bookings: $e');
    }
  }

  /// Get booking details by reference
  Future<Map<String, dynamic>> getBookingDetails(
      String bookingReference,
      ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/bookings/$bookingReference'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'] ?? data;
      } else {
        throw Exception('Failed to load booking details');
      }
    } catch (e) {
      throw Exception('Error loading booking: $e');
    }
  }

  /// Cancel a booking
  Future<Map<String, dynamic>> cancelBooking(String bookingReference) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/bookings/$bookingReference/cancel'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to cancel booking');
      }
    } catch (e) {
      throw Exception('Error cancelling booking: $e');
    }
  }

  // ========== UTILITY METHODS ==========

  /// Test connection to backend
  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('${baseUrl.replaceAll('/api', '')}/health'),
      ).timeout(const Duration(seconds: 5));

      print('🔌 Backend connection test: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Backend connection failed: $e');
      return false;
    }
  }

  /// Get backend health status
  Future<Map<String, dynamic>?> getHealthStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${baseUrl.replaceAll('/api', '')}/health'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('❌ Health check failed: $e');
      return null;
    }
  }
}
