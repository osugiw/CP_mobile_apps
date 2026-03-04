import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add this import
import 'package:mobile_apps/splash_screen.dart';
import 'package:mobile_apps/widgets/sally_logo.dart';
import 'package:mobile_apps/widgets/sally_nav_bar.dart';
import 'package:mobile_apps/widgets/home_card.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Hide the bottom system navigation bar and top status bar
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sally',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A335D)),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const SallyLogo(width: 40, height: 40),
            Expanded(
              child: Center(
                child: Text(
                  'Home',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40), // Balance the logo on the left
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Colors.grey.shade300,
            height: 1.0,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(child: HomeCard(title: 'Heart\nRate', height: 180)),
                        const SizedBox(width: 16),
                        const Expanded(child: HomeCard(title: 'HRV', height: 180)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const HomeCard(title: 'Stress Rate', height: 200, width: double.infinity),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: HomeCard(title: 'Fatigue\nLevel', height: 180)),
                        const SizedBox(width: 16),
                        const Expanded(child: HomeCard(title: 'Social\nBattery', height: 180)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SallyNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
