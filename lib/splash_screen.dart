import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart'; // Import for navigating to MyHomePage
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
    // Wait for 3 seconds, then navigate to the Home Page
    Timer(const Duration(seconds: 5), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MyHomePage(title: 'Home Page'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color logoBlue = Color(0xFF1A335D); // Approximate blue from your image

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Your icon/logo part
            SvgPicture.asset(
              'assets/images/sally_logo.svg',
              width: 200,
              height: 200,
            ),
            const SizedBox(height: 20),
            // "SALLY" Text
            const Text(
              'SALLY',
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: logoBlue,
                letterSpacing: 4.0,
              ),
            ),
            const SizedBox(height: 10),
            // Tagline
            const Text(
              'YOUR PERSONAL GATEWAY',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: logoBlue,
                letterSpacing: 1.5,
              ),
            ),
            const Text(
              'TO DAILY CLARITY',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: logoBlue,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(logoBlue),
            ),
          ],
        ),
      ),
    );
  }
}
