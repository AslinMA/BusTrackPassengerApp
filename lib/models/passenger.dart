class Passenger {
  final int? passengerId;
  final String name;
  final String phone;

  Passenger({
    this.passengerId,
    required this.name,
    required this.phone,
  });

  factory Passenger.fromJson(Map<String, dynamic> json) {
    return Passenger(
      passengerId: json['passenger_id'] as int?,
      name: json['name'] ?? json['passenger_name'] ?? '',
      phone: json['phone'] ?? json['passenger_phone'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'passenger_id': passengerId,
      'name': name,
      'phone': phone,
    };
  }
}
