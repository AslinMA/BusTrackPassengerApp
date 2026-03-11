import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'route_list_screen.dart';
import 'package:geocoding/geocoding.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController fromController = TextEditingController();
  final TextEditingController toController = TextEditingController();
  bool isLoading = false;
  String? locationError;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';

      final p = placemarks.first;

      // Build a clean place string (avoid nulls/empties)
      final parts = <String>[
        if ((p.subLocality ?? '').trim().isNotEmpty) p.subLocality!.trim(),
        if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
        if ((p.subAdministrativeArea ?? '').trim().isNotEmpty) p.subAdministrativeArea!.trim(),
        if ((p.administrativeArea ?? '').trim().isNotEmpty) p.administrativeArea!.trim(),
      ];

      final place = parts.isNotEmpty ? parts.join(', ') : (p.name ?? '');
      return place.isNotEmpty ? place : '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    } catch (_) {
      return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          locationError = 'Location services are disabled';
          fromController.text = 'Enable GPS to use current location';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            locationError = 'Location permission denied';
            fromController.text = 'Location permission required';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          locationError = 'Location permissions are permanently denied';
          fromController.text = 'Please enable location in settings';
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final placeName = await _reverseGeocode(position.latitude, position.longitude);

      setState(() {
        fromController.text = 'Current Location - $placeName';
        locationError = null;
      });
    } catch (e) {
      setState(() {
        locationError = 'Error: ${e.toString()}';
        fromController.text = 'Tap to enter location manually';
      });
    }
  }
  void _searchRoutes() {
    if (fromController.text.isEmpty || toController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter both From and To locations'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Navigate to route list screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteListScreen(
          fromLocation: fromController.text,
          toLocation: toController.text,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'BusTrack Sri Lanka',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.blue[800],
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 40),

            // Bus Icon
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_bus,
                size: 80,
                color: Colors.blue[800],
              ),
            ),

            SizedBox(height: 20),

            // Title
            Text(
              'Find Your Bus',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),

            SizedBox(height: 8),

            // Subtitle
            Text(
              'Real-time bus tracking across Sri Lanka',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),

            SizedBox(height: 40),

            // From TextField
            TextField(
              controller: fromController,
              decoration: InputDecoration(
                labelText: 'From',
                hintText: 'Enter starting location',
                prefixIcon: Icon(Icons.my_location, color: Colors.blue[800]),
                suffixIcon: IconButton(
                  icon: Icon(Icons.refresh, color: Colors.blue[800]),
                  onPressed: _getCurrentLocation,
                  tooltip: 'Refresh location',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[800]!, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[800]!, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),

            SizedBox(height: 20),

            // To TextField
            TextField(
              controller: toController,
              decoration: InputDecoration(
                labelText: 'To',
                hintText: 'Enter destination',
                prefixIcon: Icon(Icons.location_on, color: Colors.red[700]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[800]!, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),

            SizedBox(height: 32),

            // Find Buses Button
            ElevatedButton(
              onPressed: isLoading ? null : _searchRoutes,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 18),
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
              ),
              child: isLoading
                  ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Find Buses',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // Location Error Message (if any)
            if (locationError != null)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        locationError!,
                        style: TextStyle(color: Colors.orange[900], fontSize: 12),
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

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    super.dispose();
  }
}
