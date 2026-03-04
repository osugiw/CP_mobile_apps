import 'dart:async';
import 'package:flutter/material.dart';
import 'login_page.dart'; // Import to navigate to LoginPage
import 'package:flutter_svg/flutter_svg.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Wait for 3 seconds, then navigate to the Login Page
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
            SvgPicture.asset(
              'assets/images/sally_logo.svg',
              width: 180,
              height: 180,
            ),
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
