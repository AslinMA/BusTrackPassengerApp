import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/login_service.dart';
import 'models/passenger.dart';

void main() {
  runApp(const BusTrackApp());
}

class BusTrackApp extends StatelessWidget {
  const BusTrackApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BusTrack Sri Lanka',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      home: FutureBuilder<Passenger?>(
        future: LoginService.getPassenger(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data != null) {
            return  HomeScreen();
          }
          return  LoginScreen();
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
