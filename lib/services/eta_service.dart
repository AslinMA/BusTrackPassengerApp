import 'dart:math';

class ETAService {
  // Calculate distance between two points using Haversine formula (in kilometers)
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;

    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  static double _toRadians(double degrees) {
    return degrees * pi / 180;
  }

  // Calculate ETA in minutes based on distance and average speed
  static int calculateETA(double distanceKm, double averageSpeedKmh) {
    if (averageSpeedKmh <= 0) {
      averageSpeedKmh = 30; // Default speed if not available
    }

    // If bus is very far (>50km), show "--" instead
    if (distanceKm > 50) {
      return 0; // Return 0 to indicate "out of range"
    }

    double hours = distanceKm / averageSpeedKmh;
    int minutes = (hours * 60).round();

    // Cap at 120 minutes (2 hours) for realistic display
    if (minutes > 120) {
      return 0; // Out of range
    }

    return minutes > 0 ? minutes : 1; // Minimum 1 minute
  }

  // Calculate ETA from bus location to user location
  static int calculateBusETA(
      double busLat,
      double busLon,
      double userLat,
      double userLon,
      double busSpeed,
      ) {
    double distance = calculateDistance(busLat, busLon, userLat, userLon);

    // For debugging/testing: if distance is too far, return 0
    if (distance > 50) {
      return 0;
    }

    return calculateETA(distance, busSpeed);
  }

  // Format distance for display
  static String formatDistance(double distanceKm) {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()} m';
    } else {
      return '${distanceKm.toStringAsFixed(1)} km';
    }
  }
}
