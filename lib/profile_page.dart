import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mobile_apps/widgets/sally_logo.dart';

class UserProfile {
  final String name;
  final String email;
  final String address;
  final String birthDate;
  final int age;
  final String gender;
  final String profileImageUrl;

  UserProfile({
    required this.name,
    required this.email,
    required this.address,
    required this.birthDate,
    required this.age,
    required this.gender,
    required this.profileImageUrl,
  });

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      address: data['address'] ?? '',
      birthDate: data['birthDate'] ?? '',
      age: data['age'] ?? 0,
      gender: data['gender'] ?? '',
      profileImageUrl: data['profileImageUrl'] ?? '',
    );
  }

  UserProfile copyWith({
    String? name,
    String? email,
    String? address,
    String? birthDate,
    int? age,
    String? gender,
    String? profileImageUrl,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      address: address ?? this.address,
      birthDate: birthDate ?? this.birthDate,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late UserProfile _profile;
  bool _isEditing = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    Map<String, dynamic> dummyData = {
      "name": "Jane Doe",
      "email": "jane.doe@rice.edu",
      "address": "6100 Main St, Houston, TX 77005",
      "birthDate": "January 15, 1998",
      "age": 28,
      "gender": "Female",
      "profileImageUrl": "assets/images/profile-round-1342-svgrepo-com.svg",
    };
    setState(() {
      _profile = UserProfile.fromMap(dummyData);
      _updateControllers();
    });
  }

  void _updateControllers() {
    _nameController.text = _profile.name;
    _emailController.text = _profile.email;
    _addressController.text = _profile.address;
    _birthDateController.text = _profile.birthDate;
    _ageController.text = _profile.age.toString();
    _genderController.text = _profile.gender;
  }

  void _toggleEdit() {
    if (_isEditing) {
      // Saving
      setState(() {
        _profile = _profile.copyWith(
          name: _nameController.text,
          email: _emailController.text,
          address: _addressController.text,
          birthDate: _birthDateController.text,
          age: int.tryParse(_ageController.text) ?? _profile.age,
          gender: _genderController.text,
        );
        _isEditing = false;
      });
      // Here you would normally send the updated _profile to the server
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated locally!')),
      );
    } else {
      // Start editing
      setState(() {
        _isEditing = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color logoBlue = Color(0xFF1A335D);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const SallyLogo(width: 40, height: 40),
            const Expanded(
              child: Center(
                child: Text(
                  'Profile',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _toggleEdit,
              icon: Icon(_isEditing ? Icons.save : Icons.edit, color: logoBlue),
            ),
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
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EEF8),
                    shape: BoxShape.circle,
                    border: Border.all(color: logoBlue, width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SvgPicture.asset(
                      _profile.profileImageUrl,
                      colorFilter: const ColorFilter.mode(logoBlue, BlendMode.srcIn),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _isEditing
                  ? TextField(
                      controller: _nameController,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: logoBlue),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: "Name"),
                    )
                  : Text(
                      _profile.name,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: logoBlue),
                    ),
              const SizedBox(height: 40),
              _buildInfoField("Email", _emailController, Icons.email_outlined),
              _buildInfoField("Address", _addressController, Icons.location_on_outlined),
              _buildInfoField("Birth Date", _birthDateController, Icons.cake_outlined),
              _buildInfoField("Age", _ageController, Icons.calendar_today_outlined, isNumber: true),
              _buildInfoField("Gender", _genderController, Icons.person_outline),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("LOGOUT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoField(String label, TextEditingController controller, IconData icon, {bool isNumber = false}) {
    const Color logoBlue = Color(0xFF1A335D);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: logoBlue, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                _isEditing
                    ? TextField(
                        controller: controller,
                        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                      )
                    : Text(
                        controller.text,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
                      ),
                if (!_isEditing) const Divider(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
