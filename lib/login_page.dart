import 'package:flutter/material.dart';
import 'package:mobile_apps/widgets/sally_logo.dart';
import 'package:mobile_apps/widgets/sally_button.dart';
import 'main.dart'; // Import to navigate to MyHomePage

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // Dummy credentials
  final String _dummyUsername = "admin";
  final String _dummyPassword = "password";

  void _login() {
    String username = _usernameController.text;
    String password = _passwordController.text;

    if (username == _dummyUsername && password == _dummyPassword) {
      // Successful login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MyHomePage(title: 'Home Page'),
        ),
      );
    } else {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid username or password'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color logoBlue = Color(0xFF1A335D);
    const Color cardGrey = Color(0xFFD9D9D9);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 60.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Reusable Owl Logo
              const SallyLogo(width: 100, height: 100),
              const SizedBox(height: 5),
              // "Welcome Owls!"
              const Text(
                'Welcome Owls!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: logoBlue,
                ),
              ),
              const SizedBox(height: 10),
              // Login Card
              Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: cardGrey,
                  borderRadius: BorderRadius.circular(15.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Username/Email',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Reusable Login Button
                    Center(
                      child: SallyButton(
                        text: 'LOGIN',
                        onPressed: _login,
                        width: 200,
                      ),
                    ),
                    const SizedBox(height: 15),
                    // Create account text
                    Center(
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(color: Colors.black, fontSize: 12),
                          children: [
                            TextSpan(text: "Don't have an account? Create an account "),
                            TextSpan(
                              text: "here",
                              style: TextStyle(color: Colors.blue),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              // Bottom Footer
              const Text(
                'Part of Phi Lab at',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              // Rice University Image Logo
              Image.asset(
                'assets/images/RiceStackedHoriz_Blue.png',
                width: 200,
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
