import 'dart:async';
import 'package:flutter/material.dart';
import 'login_page.dart'; 
import 'package:mobile_apps/widgets/sally_logo.dart'; // Import SallyLogo

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginPage(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color logoBlue = Color(0xFF1A335D);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Use the reusable SallyLogo widget
            const SallyLogo(width: 180, height: 180),
            const SizedBox(height: 10),
            const Text(
              'SALLY',
              style: TextStyle(
                fontSize: 60,
                fontWeight: FontWeight.w900,
                color: logoBlue,
                letterSpacing: 4.0,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'YOUR PERSONAL GATEWAY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: logoBlue,
                letterSpacing: 1.2,
              ),
            ),
            const Text(
              'TO DAILY CLARITY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: logoBlue,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 50),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(logoBlue),
            ),
          ],
        ),
      ),
    );
  }
}
