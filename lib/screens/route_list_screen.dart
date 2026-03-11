import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import 'tracking_screen.dart';

class RouteListScreen extends StatefulWidget {
  final String fromLocation;
  final String toLocation;


  RouteListScreen({
    required this.fromLocation,
    required this.toLocation,
  });

  @override
  _RouteListScreenState createState() => _RouteListScreenState();
}

class _RouteListScreenState extends State<RouteListScreen> {
  final ApiService apiService = ApiService();
  List<dynamic> routes = [];

  Map<int, Map<String, dynamic>> routeBusData = {};
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    print('🚀 PASSENGER APP: RouteListScreen initialized');
    print('📍 From: ${widget.fromLocation}');
    print('📍 To: ${widget.toLocation}');
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    print('\n========== LOADING ROUTES ==========');
    print('📍 Base URL: ${ApiService.baseUrl}');
    print('🔄 Starting route load process...');

    setState(() {
      isLoading = true;
      errorMessage = null;
      routeBusData.clear();
    });

    try {
      print('\n🔌 STEP 1: Testing backend connection...');
      bool connected = await apiService.testConnection();
      print('📡 Connection result: $connected');

      if (!connected) {
        print('❌ Connection test FAILED!');
        setState(() {
          isLoading = false;
          errorMessage = 'Cannot connect to server. Please check:\n'
              '1. Backend server is running\n'
              '2. Correct backend URL\n'
              '3. Internet connection';
        });
        return;
      }

      print('✅ Connection test PASSED!');

      print('\n📞 STEP 2: Fetching all routes from API...');
      List<dynamic> fetchedRoutes = await apiService.getAllRoutes();
      print('📦 Received ${fetchedRoutes.length} routes from server');

      if (fetchedRoutes.isNotEmpty) {
        print('📋 First route: ${fetchedRoutes[0]}');
      }

      print('\n🔍 STEP 3: Filtering routes...');
      List<dynamic> filteredRoutes = fetchedRoutes.where((route) {
        String routeName = (route['route_name'] ?? '').toLowerCase();
        String startLoc = (route['start_location'] ?? '').toLowerCase();
        String endLoc = (route['end_location'] ?? '').toLowerCase();

        String from = widget.fromLocation.toLowerCase();
        String to = widget.toLocation.toLowerCase();

        bool matches = (routeName.contains(from) || startLoc.contains(from)) &&
            (routeName.contains(to) || endLoc.contains(to));

        if (matches) {
          print('✅ Match found: ${route['route_name']}');
        }

        return matches;
      }).toList();

      print('🎯 Filtered routes: ${filteredRoutes.length}');

      List<dynamic> finalRoutes =
      filteredRoutes.isNotEmpty ? filteredRoutes : fetchedRoutes;

      setState(() {
        routes = finalRoutes;
        isLoading = false;
      });

      print('\n🚌 STEP 4: Loading active buses for each route with direction...');
      for (var route in finalRoutes) {
        _loadRouteBusData(route['route_id']);
      }

      print('✅ Routes loaded successfully!');
      print('📊 Final route count: ${routes.length}');
      print('========== LOAD COMPLETE ==========\n');
    } catch (e, stackTrace) {
      print('\n❌ ========== ERROR OCCURRED ==========');
      print('❌ Error message: $e');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Stack trace:');
      print(stackTrace);
      print('========================================\n');

      setState(() {
        isLoading = false;
        errorMessage = 'Error loading routes:\n${e.toString()}';
      });
    }
  }

  Future<void> _loadRouteBusData(int routeId) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/routes/$routeId/buses').replace(
        queryParameters: {
          'from': widget.fromLocation.trim(),
          'to': widget.toLocation.trim(),
        },
      );

      print('🧭 Loading buses with direction filter: $uri');

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      print('📡 Route bus response [$routeId]: ${response.statusCode}');
      print('📦 Route bus body [$routeId]: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          List<dynamic> buses = data['data'];

          if (buses.isNotEmpty) {
            int totalSeats = 0;
            int activeBusCount = buses.length;

            for (var bus in buses) {
              int seats = _parseInt(bus['seats_available']);
              totalSeats += seats;
            }

            setState(() {
              routeBusData[routeId] = {
                'active_buses': activeBusCount,
                'total_available_seats': totalSeats,
                'buses': buses,
              };
            });

            print('✅ Route $routeId: $activeBusCount buses, $totalSeats seats');
          } else {
            setState(() {
              routeBusData[routeId] = {
                'active_buses': 0,
                'total_available_seats': 0,
                'buses': <dynamic>[],
              };
            });

            print('ℹ️ Route $routeId: no buses in this direction');
          }
        }
      }
    } catch (e) {
      print('⚠️ Failed to load bus data for route $routeId: $e');
    }
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          'Available Routes',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue[800],
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[800],
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.my_location, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.fromLocation,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.red[300], size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.toLocation,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.blue[800]),
                  SizedBox(height: 16),
                  Text(
                    'Searching for buses...',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
                : errorMessage != null
                ? Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red[300],
                    ),
                    SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadRoutes,
                      icon: Icon(Icons.refresh),
                      label: Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            )
                : routes.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.directions_bus_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No routes found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Try searching for a different route',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadRoutes,
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: routes.length,
                itemBuilder: (context, index) {
                  final route = routes[index];
                  return _buildRouteCard(route);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(Map<String, dynamic> route) {
    final routeId = route['route_id'];
    final busData = routeBusData[routeId];

    final activeBuses = busData?['active_buses'] ?? 0;
    final availableSeats = busData?['total_available_seats'] ?? 0;
    final isLoadingBusData = busData == null;

    final distanceKm =
    _parseDouble(route['distance_km'] ?? route['total_distance_km']);

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: activeBuses <= 0
            ? null
            : () {
          print('🚌 User tapped on route: ${route['route_name']}');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TrackingScreen(
                route: route,
                fromLocation: widget.fromLocation,
                toLocation: widget.toLocation,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: (!isLoadingBusData && activeBuses == 0) ? 0.7 : 1.0,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            route['route_name'] ?? 'Unknown Route',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[900],
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Route ${route['route_number'] ?? 'N/A'}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 16, color: Colors.grey[400]),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.straighten, size: 18, color: Colors.grey[600]),
                    SizedBox(width: 6),
                    Text(
                      '${distanceKm.toStringAsFixed(1)} km',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    SizedBox(width: 16),
                    Icon(Icons.access_time, size: 18, color: Colors.grey[600]),
                    SizedBox(width: 6),
                    Text(
                      _calculateEstimatedTime(distanceKm),
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Divider(),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.directions_bus,
                            size: 20,
                            color: activeBuses > 0
                                ? Colors.green[700]
                                : Colors.grey,
                          ),
                          SizedBox(width: 8),
                          Text(
                            isLoadingBusData
                                ? 'Loading...'
                                : '$activeBuses Active ${activeBuses == 1 ? 'Bus' : 'Buses'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: activeBuses > 0
                                  ? Colors.black87
                                  : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_seat,
                            size: 20,
                            color: availableSeats > 0
                                ? Colors.blue[700]
                                : Colors.grey,
                          ),
                          SizedBox(width: 8),
                          Text(
                            isLoadingBusData
                                ? '...'
                                : '$availableSeats Seats Available',
                            style: TextStyle(
                              fontSize: 14,
                              color: availableSeats > 0
                                  ? Colors.black87
                                  : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isLoadingBusData && activeBuses == 0)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Container(
                      padding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.red[700]),
                          SizedBox(width: 6),
                          Text(
                            'No active buses in this direction',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _calculateEstimatedTime(double distanceKm) {
    if (distanceKm <= 0) return '--';

    double hours = distanceKm / 25;
    int minutes = (hours * 60).ceil();

    if (minutes < 60) {
      return '~$minutes mins';
    } else {
      int hrs = minutes ~/ 60;
      int mins = minutes % 60;
      return '~${hrs}h ${mins}m';
    }
  }
}