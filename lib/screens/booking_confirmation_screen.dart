import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

class BookingConfirmationScreen extends StatelessWidget {
  final Map<String, dynamic> booking;

  BookingConfirmationScreen({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Booking Confirmed', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green[700],
        iconTheme: IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Success Animation
            Container(
              padding: EdgeInsets.all(32),
              color: Colors.green[50],
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.green[700],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Booking Successful!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your seat has been reserved',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),

            // Booking Details Card
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  // Booking Reference
                  Card(
                    elevation: 4,
                    color: Colors.blue[800],
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            'Booking Reference',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                booking['booking_reference'] ?? 'N/A',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              IconButton(
                                icon: Icon(Icons.copy, color: Colors.white),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: booking['booking_reference']),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Booking reference copied!')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Trip Details
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip Details',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Divider(),
                          _buildDetailRow(Icons.directions_bus, 'Bus Number', booking['bus_number'] ?? 'N/A'),
                          _buildDetailRow(Icons.route, 'Route', booking['route_name'] ?? 'N/A'),
                          _buildDetailRow(Icons.location_on, 'Pickup Stop', booking['pickup_stop_name'] ?? 'N/A'),
                          if (booking['dropoff_stop_name'] != null)
                            _buildDetailRow(Icons.flag, 'Drop-off Stop', booking['dropoff_stop_name']),
                          _buildDetailRow(Icons.calendar_today, 'Travel Date',
                              booking['travel_date'] ?? DateTime.now().toIso8601String().split('T')[0]),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Passenger Details
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Passenger Details',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Divider(),
                          _buildDetailRow(Icons.person, 'Name', booking['passenger_name'] ?? 'N/A'),
                          _buildDetailRow(Icons.phone, 'Phone', booking['passenger_phone'] ?? 'N/A'),
                          _buildDetailRow(Icons.people, 'Number of Passengers',
                              booking['number_of_passengers'].toString()),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Payment Details
                  Card(
                    elevation: 2,
                    color: Colors.amber[50],
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Fare',
                                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Rs. ${booking['fare_amount']?.toStringAsFixed(2) ?? '0.00'}',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber[900],
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.amber[700],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.payments, color: Colors.white, size: 32),
                                    SizedBox(height: 4),
                                    Text(
                                      'Pay Cash',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber[700]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.amber[900]),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Please pay cash to the driver when you board the bus',
                                    style: TextStyle(fontSize: 14, color: Colors.amber[900]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Important Instructions
                  Card(
                    elevation: 2,
                    color: Colors.blue[50],
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info, color: Colors.blue[800]),
                              SizedBox(width: 8),
                              Text(
                                'Important Instructions',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[800],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          _buildInstructionItem('Show this booking reference to the driver'),
                          _buildInstructionItem('Arrive at the pickup stop 5 minutes early'),
                          _buildInstructionItem('Have exact cash ready for payment'),
                          _buildInstructionItem('Keep your phone handy for tracking the bus'),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // TODO: Track bus
                            Navigator.pop(context);
                          },
                          icon: Icon(Icons.my_location),
                          label: Text('Track Bus'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.all(16),
                            foregroundColor: Colors.blue[800],
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.popUntil(context, (route) => route.isFirst);
                          },
                          icon: Icon(Icons.home),
                          label: Text('Go Home'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.all(16),
                            backgroundColor: Colors.blue[800],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(fontSize: 18, color: Colors.blue[800])),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }
}
