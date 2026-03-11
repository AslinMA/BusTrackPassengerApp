import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:math';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:ui' as ui;
import 'booking_screen.dart';

class TrackingScreen extends StatefulWidget {
  final Map<String, dynamic> route;
  final int? bookingId;
  final String? toLocation;
  final String? fromLocation;

  const TrackingScreen({
    Key? key,
    required this.route,
    this.fromLocation,
    this.bookingId,
    this.toLocation,
  }) : super(key: key);

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<Map<String, dynamic>> _activeBuses = [];
  List<Map<String, dynamic>> _stops = [];
  Timer? _locationTimer;
  Timer? _passengerLocationTimer;
  IO.Socket? _socket;
  bool _isLoading = true;
  Position? _userLocation;
  Map<String, dynamic>? _nearestStop;
  int? _selectedBusIndex;

  // ✅ NEW: Booking details
  Map<String, dynamic>? _myBooking;
  bool _isLoadingBooking = false;

  BitmapDescriptor? _passengerIcon;
  BitmapDescriptor? _busIcon;

  final String baseUrl = 'https://bustrack-backend-production.up.railway.app/api';

  final String googleApiKey = "AIzaSyAdHYOEiD2KR9po_zblfuywen25inzQECU";
  bool _isDrawingLine = false;
  DateTime? _lastPolylineTime;

  @override
  void initState() {
    super.initState();
    print('🚀 TrackingScreen initialized with bookingId: ${widget.bookingId}');

    _createMarkerIcons();
    _getUserLocation();
    _loadStops();
    _loadActiveBuses();
    _startRealtimeTracking();
    _setupWebSocket();

    if (widget.bookingId != null) {
      _loadMyBooking();
      _startSendingPassengerLocation();

      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          print('🔄 Force reloading buses and markers after booking...');
          _loadActiveBuses();
        }
      });
    }
  }

  Future<List<LatLng>> _getRoadPolyline(LatLng origin, LatLng dest) async {
    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/directions/json"
          "?origin=${origin.latitude},${origin.longitude}"
          "&destination=${dest.latitude},${dest.longitude}"
          "&mode=driving"
          "&key=$googleApiKey",
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 12));

      // ✅ If HTTP failed
      if (res.statusCode != 200) {
        print("❌ Directions HTTP error: ${res.statusCode}");
        print("❌ Body: ${res.body}");
        return [];
      }

      final data = json.decode(res.body);

      // ✅ Print Google response status (VERY IMPORTANT)
      final status = data["status"];
      final errorMessage = data["error_message"];
      print("🧭 Directions status: $status");
      if (errorMessage != null) {
        print("🧭 Directions error_message: $errorMessage");
      }

      // ✅ Not OK = no polyline
      if (status != "OK") {
        return [];
      }

      final routes = data["routes"];
      if (routes == null || routes.isEmpty) {
        print("⚠️ Directions returned 0 routes");
        return [];
      }

      final overview = routes[0]["overview_polyline"];
      if (overview == null || overview["points"] == null) {
        print("⚠️ Directions missing overview_polyline.points");
        return [];
      }

      final encoded = overview["points"] as String;

      final decoded = PolylinePoints().decodePolyline(encoded);

      if (decoded.isEmpty) {
        print("⚠️ Polyline decoded empty");
        return [];
      }

      final points = decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();

      print("✅ Road polyline points: ${points.length}");
      return points;
    } catch (e) {
      print("❌ Directions exception: $e");
      return [];
    }
  }
  Future<void> _drawBusToPassengerLine() async {
    if (_isDrawingLine) return;
    if (_userLocation == null) return;
    if (_activeBuses.isEmpty) return;

    // 🔒 Prevent too frequent Google API calls (every 8 seconds max)
    final now = DateTime.now();
    if (_lastPolylineTime != null &&
        now.difference(_lastPolylineTime!).inSeconds < 8) {
      print("⏳ Polyline skipped (throttle)");
      return;
    }
    _lastPolylineTime = now;

    _isDrawingLine = true;

    try {
      Map<String, dynamic> bus;

      // ✅ If passenger has booking → use that bus
      if (widget.bookingId != null && _myBooking != null) {
        bus = _activeBuses.firstWhere(
              (b) => b['trip_id'] == _myBooking!['trip_id'],
          orElse: () => _activeBuses.first,
        );
      } else {
        // ✅ Otherwise use selected bus OR first bus
        bus = _activeBuses[_selectedBusIndex ?? 0];
      }

      final busLat =
      _parseDouble(bus['current_latitude'] ?? bus['latitude']);
      final busLng =
      _parseDouble(bus['current_longitude'] ?? bus['longitude']);

      // 🛑 Safety check
      if (busLat == 0.0 || busLng == 0.0) {
        print("❌ Invalid bus coordinates");
        return;
      }

      final busPos = LatLng(busLat, busLng);
      final passengerPos = LatLng(
        _userLocation!.latitude,
        _userLocation!.longitude,
      );

      // 🚗 Try getting real road polyline
      final roadPoints = await _getRoadPolyline(busPos, passengerPos);

      // 🔁 Fallback: straight line if Google fails
      final polylinePoints =
      roadPoints.isNotEmpty ? roadPoints : [busPos, passengerPos];

      if (!mounted) return;
      print("✅ Polyline points count: ${polylinePoints.length}");
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId("bus_to_passenger"),
            points: polylinePoints,
            width: 6,
            color: Colors.blue,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ),
        };
      });
    } catch (e) {
      print("❌ polyline error: $e");
    } finally {
      _isDrawingLine = false;
    }
  }
  Future<void> _loadMyBooking() async {
    if (widget.bookingId == null) return;

    setState(() => _isLoadingBooking = true);

    try {
      final url = Uri.parse('$baseUrl/bookings/${widget.bookingId}');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      print('📡 Booking API Response: ${response.statusCode}');
      print('📡 Booking API Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _myBooking = data['data'];
            _isLoadingBooking = false;
          });
          print('✅ Booking loaded: ${_myBooking?['booking_id']}');
        }
      }
    } catch (e) {
      print('❌ Error loading booking: $e');
      setState(() => _isLoadingBooking = false);
    }
  }

  Future<void> _cancelBooking() async {
    if (widget.bookingId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final url = Uri.parse('$baseUrl/bookings/${widget.bookingId}/cancel');
      final response = await http.put(url);

      print('📡 Cancel Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Booking cancelled successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        throw Exception('Failed to cancel booking');
      }
    } catch (e) {
      print('❌ Error cancelling booking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markBusTaken() async {
    if (widget.bookingId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[700]),
            const SizedBox(width: 12),
            const Text('Confirm Payment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Have you boarded the bus and paid the driver?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[700]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments, color: Colors.amber[900]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Amount: Rs. ${_parseDouble(_myBooking?['fare_amount']).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Paid'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final url = Uri.parse('$baseUrl/bookings/${widget.bookingId}/payment');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'payment_status': 'PAID',
          'is_payment_collected': true,
        }),
      );

      print('📡 Payment Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 32),
                  const SizedBox(width: 12),
                  const Text('Payment Confirmed!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Thank you for using our service!'),
                  const SizedBox(height: 16),
                  Text(
                    'Have a safe journey! 🚌',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.blue[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception('Failed to update payment');
      }
    } catch (e) {
      print('❌ Error updating payment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _createMarkerIcons() async {
    _passengerIcon = await _createCustomMarker(
      icon: Icons.person,
      backgroundColor: Colors.green,
      iconColor: Colors.white,
    );

    _busIcon = await _createCustomMarker(
      icon: Icons.directions_bus,
      backgroundColor: Colors.orange,
      iconColor: Colors.white,
    );

    print('✅ Custom marker icons created');

    if (mounted) {
      _updateMapMarkers();
    }
  }

  Future<BitmapDescriptor> _createCustomMarker({
    required IconData icon,
    required Color backgroundColor,
    required Color iconColor,
    int size = 120,
  }) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final paint = Paint()..color = backgroundColor;

    canvas.drawCircle(
      Offset(size / 2, size / 2),
      size / 2,
      paint,
    );

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(
      Offset(size / 2, size / 2),
      size / 2,
      borderPaint,
    );

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.6,
        fontFamily: icon.fontFamily,
        color: iconColor,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permission denied');
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition();
      print('📍 User location obtained: ${position.latitude}, ${position.longitude}');

      setState(() {
        _userLocation = position;
      });

      _findNearestStop();
      _updateMapMarkers();
      _drawBusToPassengerLine();
    } catch (e) {
      print('❌ Location error: $e');
    }
  }

  Future<void> _loadStops() async {
    try {
      final url = Uri.parse('$baseUrl/routes/${widget.route['route_id']}/stops');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _stops = List<Map<String, dynamic>>.from(data['data']);
          });
          print('✅ Loaded ${_stops.length} stops');
          _findNearestStop();
          _updateMapMarkers();
        }
      }
    } catch (e) {
      print('❌ Error loading stops: $e');
    }
  }

  void _findNearestStop() {
    if (_userLocation == null || _stops.isEmpty) return;

    double minDistance = double.infinity;
    Map<String, dynamic>? nearest;

    for (var stop in _stops) {
      double distance = Geolocator.distanceBetween(
        _userLocation!.latitude,
        _userLocation!.longitude,
        _parseDouble(stop['latitude']),
        _parseDouble(stop['longitude']),
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearest = stop;
      }
    }

    setState(() {
      _nearestStop = nearest;
    });
  }

  Future<void> _loadActiveBuses() async {
    try {
      print('🔄 Loading active buses for route ${widget.route['route_id']}...');

      final uri = Uri.parse('$baseUrl/routes/${widget.route['route_id']}/buses').replace(
        queryParameters: {
          if ((widget.fromLocation ?? '').trim().isNotEmpty)
            'from': widget.fromLocation!.trim(),
          if ((widget.toLocation ?? '').trim().isNotEmpty)
            'to': widget.toLocation!.trim(),
        },
      );

      print('🧭 Loading active buses with direction filter: $uri');

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      print('📡 Bus API Response: ${response.statusCode}');
      print('📡 Bus API Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          List<Map<String, dynamic>> buses =
          List<Map<String, dynamic>>.from(data['data']);

          print('✅ Found ${buses.length} active buses');

          for (var bus in buses) {
            print(
                '📦 Bus data: ${bus['bus_number']} - lat: ${bus['latitude']}, lng: ${bus['longitude']}');
            await _loadBusSeatInfo(bus);
          }

          setState(() {
            _activeBuses = buses;
            _isLoading = false;
          });

          _updateMapMarkers();
          _drawBusToPassengerLine();

          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted && _mapController != null) {
              _updateMapMarkers();
            }
          });
        } else {
          print('❌ API returned success: false');
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading buses: $e');
      setState(() => _isLoading = false);
    }
  }
  Future<void> _loadBusSeatInfo(Map<String, dynamic> bus) async {
    try {
      final url = Uri.parse('$baseUrl/trips/${bus['trip_id']}/seats');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          bus['seat_info'] = data['data'];
        }
      }
    } catch (e) {
      print('❌ Error loading seat info: $e');
    }
  }

  void _startSendingPassengerLocation() {
    print('🚶 Starting passenger location tracking...');
    _passengerLocationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _sendPassengerLocation();
    });
    _sendPassengerLocation();
  }

  Future<void> _sendPassengerLocation() async {
    if (_userLocation == null) {
      print('⚠️ Cannot send passenger location: user location is null');
      return;
    }
    if (widget.bookingId == null) {
      print('⚠️ Cannot send passenger location: bookingId is null');
      return;
    }

    try {
      final url = Uri.parse('$baseUrl/bookings/${widget.bookingId}/location');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'latitude': _userLocation!.latitude,
          'longitude': _userLocation!.longitude,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Passenger location sent: ${_userLocation!.latitude}, ${_userLocation!.longitude}');
      } else {
        print('⚠️ Failed to send passenger location: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error sending passenger location: $e');
    }
  }

  void _setupWebSocket() {
    try {
      _socket = IO.io('https://bustrack-backend-production.up.railway.app', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      });

      _socket?.connect();

      _socket?.on('connect', (_) {
        print('🔌 WebSocket connected');
        _socket?.emit('route:subscribe', {'route_id': widget.route['route_id']});
      });

      _socket?.on('bus:location:live', (data) {
        print('📍 WebSocket location update received: $data');
        _handleLocationUpdate(Map<String, dynamic>.from(data));
      });

      _socket?.on('disconnect', (_) {
        print('❌ WebSocket disconnected');
      });

      _socket?.on('error', (error) {
        print('❌ WebSocket error: $error');
      });
    } catch (e) {
      print('❌ WebSocket setup error: $e');
    }
  }

  void _handleLocationUpdate(Map<String, dynamic> data) {
    print('📡 Processing location update: $data');

    setState(() {
      final busIndex = _activeBuses.indexWhere(
              (bus) => bus['trip_id'] == data['trip_id'] || bus['bus_id'] == data['bus_id']
      );

      if (busIndex != -1) {
        _activeBuses[busIndex]['current_latitude'] = data['latitude'];
        _activeBuses[busIndex]['current_longitude'] = data['longitude'];
        _activeBuses[busIndex]['latitude'] = data['latitude'];
        _activeBuses[busIndex]['longitude'] = data['longitude'];
        _activeBuses[busIndex]['speed_kmh'] = data['speed'];
        _activeBuses[busIndex]['last_location_update'] = DateTime.now().toIso8601String();

        print('✅ Updated bus ${busIndex + 1} position: ${data['latitude']}, ${data['longitude']}');
      } else {
        print('⚠️ Bus not found. trip_id: ${data['trip_id']}, bus_id: ${data['bus_id']}');
      }

      _updateMapMarkers();
      _drawBusToPassengerLine();
    });
  }

  void _startRealtimeTracking() {
    _locationTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      print('⏰ Periodic update triggered');
      _loadActiveBuses();
      _getUserLocation();
    });
  }

  void _updateMapMarkers() {
    print('\n🔍 === UPDATE MARKERS CALLED ===');
    print('🔍 User location: ${_userLocation?.latitude}, ${_userLocation?.longitude}');
    print('🔍 Active buses count: ${_activeBuses.length}');

    final markers = <Marker>{};

    for (var i = 0; i < _activeBuses.length; i++) {
      try {
        var bus = _activeBuses[i];
        print('\n🚌 Processing bus $i: ${bus['bus_number']}');

        var latValue = bus['current_latitude'] ?? bus['latitude'];
        var lngValue = bus['current_longitude'] ?? bus['longitude'];

        print('   Raw values - lat: $latValue (${latValue.runtimeType}), lng: $lngValue (${lngValue.runtimeType})');

        if (latValue == null || lngValue == null) {
          print('❌ Bus has null coordinates');
          continue;
        }

        // ✅ FIXED: Use _parseDouble instead of double.parse
        double busLat = _parseDouble(latValue);
        double busLng = _parseDouble(lngValue);

        print('✅ Parsed coordinates: $busLat, $busLng');

        final busMarker = Marker(
          markerId: MarkerId('bus_${i}_${bus['trip_id']}'),
          position: LatLng(busLat, busLng),
          icon: _busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: '🚌 ${bus['bus_number'] ?? 'Bus'}',
            snippet: 'Driver: ${bus['driver_name'] ?? 'Unknown'}',
          ),
          anchor: const Offset(0.5, 0.5),
          zIndex: 1.0,
        );

        markers.add(busMarker);
        print('✅ Bus marker added successfully!');

      } catch (e, stackTrace) {
        print('❌ ERROR adding bus marker: $e');
        print('Stack trace: $stackTrace');
      }
    }

    if (_userLocation != null) {
      try {
        print('\n📍 Adding user marker at: ${_userLocation!.latitude}, ${_userLocation!.longitude}');

        final userMarker = Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(_userLocation!.latitude, _userLocation!.longitude),
          icon: _passengerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: '📍 You'),
          anchor: const Offset(0.5, 0.5),
          zIndex: 2.0,
        );

        markers.add(userMarker);
        print('✅ User marker added successfully!');

      } catch (e, stackTrace) {
        print('❌ ERROR adding user marker: $e');
        print('Stack trace: $stackTrace');
      }
    }

    print('\n🔍 Final markers count: ${markers.length}');
    print('🔍 Marker IDs: ${markers.map((m) => m.markerId.value).toList()}');

    setState(() {
      _markers = markers;
    });

    if (_userLocation != null && _mapController != null && markers.length >= 2) {
      try {
        if (_activeBuses.isNotEmpty) {
          Map<String, dynamic> bus;

          if (widget.bookingId != null && _myBooking != null) {
            bus = _activeBuses.firstWhere(
                  (b) => b['trip_id'] == _myBooking!['trip_id'],
              orElse: () => _activeBuses.first,
            );
          } else {
            bus = _activeBuses[_selectedBusIndex ?? 0];
          }
          // ✅ FIXED: Use _parseDouble
          var busLat = _parseDouble(bus['current_latitude'] ?? bus['latitude']);
          var busLng = _parseDouble(bus['current_longitude'] ?? bus['longitude']);

          double distance = Geolocator.distanceBetween(
            _userLocation!.latitude,
            _userLocation!.longitude,
            busLat,
            busLng,
          );

          print('📏 Distance between user and bus: ${distance.toStringAsFixed(1)} meters');

          double centerLat = (_userLocation!.latitude + busLat) / 2;
          double centerLng = (_userLocation!.longitude + busLng) / 2;

          double zoom = 18;
          if (distance > 10) zoom = 17;
          if (distance > 50) zoom = 16;
          if (distance > 100) zoom = 15;
          if (distance > 500) zoom = 14;
          if (distance > 1000) zoom = 13;

          print('📍 Camera center: $centerLat, $centerLng with zoom: $zoom');

          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(centerLat, centerLng),
              zoom,
            ),
          );
        }
      } catch (e) {
        print('❌ Error centering camera: $e');
      }
    } else if (_userLocation != null && _mapController != null) {
      print('📍 Only user marker, centering on user');
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_userLocation!.latitude, _userLocation!.longitude),
          16,
        ),
      );
    }

    print('🔍 === UPDATE MARKERS COMPLETE ===\n');
  }

  // ✅ FIXED: Safe parsing helper functions
  double _parseSpeed(dynamic speed) {
    if (speed == null) return 0.0;
    if (speed is double) return speed;
    if (speed is int) return speed.toDouble();
    if (speed is String) return double.tryParse(speed) ?? 0.0;
    return 0.0;
  }

  // ✅ NEW: Generic double parser
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // ✅ FIXED: Use _parseDouble for safe conversion
  double _calculateDistanceToBus(Map<String, dynamic> bus) {
    if (_userLocation == null) return 0.0;

    var latValue = bus['current_latitude'] ?? bus['latitude'];
    var lngValue = bus['current_longitude'] ?? bus['longitude'];

    if (latValue == null || lngValue == null) return 0.0;

    // ✅ FIXED: Use _parseDouble instead of double.parse
    double busLat = _parseDouble(latValue);
    double busLng = _parseDouble(lngValue);

    double distanceMeters = Geolocator.distanceBetween(
      _userLocation!.latitude,
      _userLocation!.longitude,
      busLat,
      busLng,
    );

    return distanceMeters / 1000;
  }

  String _calculateRealETA(double distanceKm, double speedKmh) {
    if (distanceKm < 0.1) return 'Arriving now';

    double avgSpeed = speedKmh > 10 ? speedKmh * 0.7 : 25;
    int minutes = ((distanceKm / avgSpeed) * 60).ceil();

    if (minutes < 1) return 'Arriving now';
    return '$minutes mins';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Route ${widget.route['route_number']}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue[800],
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              print('🔄 Manual refresh triggered');
              _loadActiveBuses();
              _getUserLocation();
              if (widget.bookingId != null) {
                _loadMyBooking();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(6.9271, 79.8612),
              zoom: 12,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            onMapCreated: (controller) {
              print('🗺️ Map created');
              _mapController = controller;
              Future.delayed(const Duration(milliseconds: 1000), () {
                if (mounted) {
                  _updateMapMarkers();
                }
              });
            },
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          if (_nearestStop != null && widget.bookingId == null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.blue[700], size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nearest Stop',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              _nearestStop!['stop_name'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (widget.bookingId != null && _myBooking != null)
            _buildMyBookingSheet()
          else if (widget.bookingId == null && _activeBuses.isNotEmpty)
            _buildActiveBusesList(),
        ],
      ),
    );
  }

  Widget _buildMyBookingSheet() {
    if (_myBooking == null) return const SizedBox.shrink();

    Map<String, dynamic>? myBus;
    for (var bus in _activeBuses) {
      if (bus['trip_id'] == _myBooking!['trip_id']) {
        myBus = bus;
        break;
      }
    }

    final distanceKm = myBus != null ? _calculateDistanceToBus(myBus) : 0.0;
    final speedKmh = myBus != null ? _parseSpeed(myBus['speed_kmh']) : 0.0;
    final etaText = myBus != null ? _calculateRealETA(distanceKm, speedKmh) : 'Calculating...';

    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.2,
      maxChildSize: 0.7,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_circle, color: Colors.green[700], size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Your Booking',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.blue[800]!, width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.directions_bus,
                                color: Colors.orange[800],
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _myBooking!['bus_number'] ?? 'Bus',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Route ${widget.route['route_number']}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[100],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 18,
                                    color: Colors.green[800],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    etaText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[800],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            _buildInfoChip(
                              Icons.straighten,
                              '${distanceKm.toStringAsFixed(2)} km',
                              Colors.blue,
                            ),
                            const SizedBox(width: 12),
                            _buildInfoChip(
                              Icons.speed,
                              '${speedKmh.toStringAsFixed(0)} km/h',
                              Colors.purple,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Card(
                  elevation: 2,
                  color: Colors.amber[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.payments, color: Colors.amber[900], size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Fare',
                                style: TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                              Text(
                                'Rs. ${_parseDouble(_myBooking!['fare_amount']).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber[900],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber[700],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Cash',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cancelBooking,
                        icon: const Icon(Icons.cancel),
                        label: const Text('Cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _markBusTaken,
                        icon: const Icon(Icons.check_circle),
                        label: const Text('I Took the Bus'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[800], size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Click "I Took the Bus" after boarding and paying the driver',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveBusesList() {
    return DraggableScrollableSheet(
      initialChildSize: 0.3,
      minChildSize: 0.15,
      maxChildSize: 0.7,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _activeBuses.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${_activeBuses.length} Active ${_activeBuses.length == 1 ? 'Bus' : 'Buses'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }

              final bus = _activeBuses[index - 1];
              final seatInfo = bus['seat_info'];
              final isSelected = _selectedBusIndex == (index - 1);

              final distanceKm = _calculateDistanceToBus(bus);
              final speedKmh = _parseSpeed(bus['speed_kmh']);
              final etaText = _calculateRealETA(distanceKm, speedKmh);

              return Card(
                elevation: isSelected ? 8 : 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? Colors.blue[800]! : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedBusIndex = index - 1);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.directions_bus,
                                color: Colors.orange[800],
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bus['bus_number'] ?? 'Bus $index',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    bus['driver_name'] ?? 'Driver',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[100],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 16,
                                    color: Colors.green[800],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    etaText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[800],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildInfoChip(
                              Icons.speed,
                              '${speedKmh.toStringAsFixed(0)} km/h',
                              Colors.blue,
                            ),
                            const SizedBox(width: 12),
                            if (seatInfo != null)
                              _buildInfoChip(
                                Icons.event_seat,
                                '${_parseDouble(seatInfo['available_seats']).toInt()} seats',
                                _parseDouble(seatInfo['available_seats']) > 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            const SizedBox(width: 12),
                            _buildInfoChip(
                              Icons.straighten,
                              '${distanceKm.toStringAsFixed(2)} km',
                              Colors.orange,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: seatInfo != null &&
                                _parseDouble(seatInfo['available_seats']) > 0
                                ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => BookingScreen(
                                    route: widget.route,
                                    bus: bus,
                                    nearestStop: _nearestStop,
                                    toLocation: widget.toLocation,
                                  ),
                                ),
                              );
                            }
                                : null,
                            icon: const Icon(Icons.book_online),
                            label: Text(
                              seatInfo != null && _parseDouble(seatInfo['available_seats']) > 0
                                  ? 'Book Now'
                                  : 'Full - No Seats',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[800],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _passengerLocationTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _mapController?.dispose();
    super.dispose();
  }
}
