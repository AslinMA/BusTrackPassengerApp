import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'tracking_screen.dart';
import '../services/login_service.dart';
import '../models/passenger.dart';


class BookingScreen extends StatefulWidget {
  final Map<String, dynamic> route;
  final Map<String, dynamic> bus;
  final Map<String, dynamic>? nearestStop;
  final String? toLocation;

  const BookingScreen({
    Key? key,
    required this.route,
    required this.bus,
    this.nearestStop,
    this.toLocation,
  }) : super(key: key);

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  int _numberOfPassengers = 1;
  int? _selectedPickupStopId;
  int? _selectedDropoffStopId;
  List<Map<String, dynamic>> _stops = [];
  bool _isLoadingStops = true;
  bool _isBooking = false;

  final String baseUrl = 'https://bustrack-backend-production.up.railway.app/api';

  @override
  void initState() {
    super.initState();
    _loadSavedPassenger();
    _loadRouteStops();

  }

  void _autoSelectDropoff() {
    final toText = (widget.toLocation ?? '').toLowerCase().trim();
    if (toText.isEmpty || _stops.isEmpty) return;

    int? bestId;
    int bestScore = -1;

    for (final stop in _stops) {
      final name = (stop['stop_name'] ?? '').toString().toLowerCase();

      int score = 0;
      if (name.contains(toText)) score += 10;

      for (final w in toText.split(' ')) {
        final word = w.trim();
        if (word.isEmpty) continue;
        if (name.contains(word)) score += 2;
      }

      if (score > bestScore) {
        bestScore = score;
        bestId = stop['stop_id'];
      }
    }

    if (bestId != null && bestScore >= 2) {
      setState(() => _selectedDropoffStopId = bestId);
    }
  }

  double parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String formatFare(dynamic fare) {
    if (fare == null) return '0.00';
    if (fare is num) return fare.toStringAsFixed(2);
    if (fare is String) {
      final parsed = double.tryParse(fare);
      return parsed?.toStringAsFixed(2) ?? '0.00';
    }
    return '0.00';
  }
  Future<void> _loadSavedPassenger() async {
    final p = await LoginService.getPassenger();
    if (p != null && mounted) {
      setState(() {
        _nameController.text = p.name;
        _phoneController.text = p.phone;
      });
    }
  }

  Future<void> _loadRouteStops() async {
    try {
      final url = Uri.parse('$baseUrl/routes/${widget.route['route_id']}/stops');
      print('🔍 Loading stops from: $url');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          setState(() {
            _stops = List<Map<String, dynamic>>.from(data['data']);
            _isLoadingStops = false;

            // ✅ auto pickup by nearest stop (already your logic)
            if (widget.nearestStop != null) {
              _selectedPickupStopId = widget.nearestStop!['stop_id'];
            }
          });

          // ✅ auto dropoff from "To" text
          _autoSelectDropoff();

          print('✅ Loaded ${_stops.length} stops');
        } else {
          throw Exception(data['error'] ?? 'Failed to load stops');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading stops: $e');
      setState(() => _isLoadingStops = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading stops: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
  Future<void> _submitBooking() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPickupStopId == null) {
      _showError('Please select a pickup stop');
      return;
    }

    if (_selectedDropoffStopId == null) {
      _showError('Please select a dropoff stop');
      return;
    }

    if (_selectedPickupStopId == _selectedDropoffStopId) {
      _showError('Pickup and dropoff stops must be different');
      return;
    }

    setState(() => _isBooking = true);

    try {
      final url = Uri.parse('$baseUrl/bookings');

      final bookingData = {
        'trip_id': widget.bus['trip_id'],
        'passenger_name': _nameController.text.trim(),
        'passenger_phone': _phoneController.text.trim(),
        'pickup_stop_id': _selectedPickupStopId,
        'dropoff_stop_id': _selectedDropoffStopId,
        'number_of_passengers': _numberOfPassengers,
      };

      print('📤 Submitting booking: $bookingData');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(bookingData),
      ).timeout(const Duration(seconds: 15));

      print('📡 Booking response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      final data = json.decode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        final bookingId = data['data']['booking_id'];

        if (mounted) {
          Navigator.pop(context);

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 32),
                  const SizedBox(width: 12),
                  const Text('Booking Confirmed!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Booking ID: $bookingId',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildInfoRow('Bus', widget.bus['bus_number'] ?? 'N/A'),
                  _buildInfoRow('Route', widget.route['route_number'] ?? 'N/A'),
                  _buildInfoRow('Passengers', '$_numberOfPassengers'),
                  _buildInfoRow(
                    'Fare',
                    'Rs. ${formatFare(data['data']['fare_amount'])}',
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    '✅ Your seat${_numberOfPassengers > 1 ? 's are' : ' is'} confirmed!',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '📍 The driver can now track your location',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TrackingScreen(
                          route: widget.route,
                          bookingId: bookingId,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Track My Bus'),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception(data['error'] ?? 'Booking failed');
      }
    } catch (e) {
      print('❌ Booking error: $e');
      _showError('Booking failed: $e');
    } finally {
      setState(() => _isBooking = false);
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final seatInfo = widget.bus['seat_info'];
    final availableSeats = seatInfo != null ? parseDouble(seatInfo['available_seats']).toInt() : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Book Your Seat',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue[800],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoadingStops
          ? const Center(child: CircularProgressIndicator())
          : _stops.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No stops available',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'Please contact support',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadRouteStops,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.directions_bus,
                          color: Colors.blue[800],
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.bus['bus_number'] ?? 'Bus',
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
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: availableSeats > 0
                                    ? Colors.green[100]
                                    : Colors.red[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.event_seat,
                                    size: 16,
                                    color: availableSeats > 0
                                        ? Colors.green[800]
                                        : Colors.red[800],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$availableSeats seats available',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: availableSeats > 0
                                          ? Colors.green[800]
                                          : Colors.red[800],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Passenger Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  hintText: 'Enter your full name',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '0712345678',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your phone number';
                  }
                  if (value.trim().length < 10) {
                    return 'Phone number must be at least 10 digits';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Number of Passengers',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _numberOfPassengers > 1
                                ? () {
                              setState(() => _numberOfPassengers--);
                            }
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                            color: Colors.blue[800],
                          ),
                          Text(
                            '$_numberOfPassengers',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: _numberOfPassengers < availableSeats
                                ? () {
                              setState(() => _numberOfPassengers++);
                            }
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                            color: Colors.blue[800],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Journey Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _selectedPickupStopId,
                decoration: InputDecoration(
                  labelText: 'Pickup Stop',
                  prefixIcon: const Icon(Icons.location_on, color: Colors.green),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                isExpanded: true,
                items: _stops.map((stop) {
                  return DropdownMenuItem<int>(
                    value: stop['stop_id'],
                    child: Text(
                      stop['stop_name'],
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedPickupStopId = value);
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a pickup stop';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _selectedDropoffStopId,
                decoration: InputDecoration(
                  labelText: 'Dropoff Stop',
                  prefixIcon: const Icon(Icons.location_on, color: Colors.red),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                isExpanded: true,
                items: _stops.map((stop) {
                  return DropdownMenuItem<int>(
                    value: stop['stop_id'],
                    child: Text(
                      stop['stop_name'],
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedDropoffStopId = value);
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a dropoff stop';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isBooking ? null : _submitBooking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isBooking
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Confirm Booking',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
