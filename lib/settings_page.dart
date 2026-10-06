import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'widgets/sally_logo.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Color kBlue = Color(0xFF1A335D);

  final _nameCtrl    = TextEditingController();
  final _phone1Ctrl  = TextEditingController();
  final _phone2Ctrl  = TextEditingController();
  final _phone3Ctrl  = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phone1Ctrl.dispose();
    _phone2Ctrl.dispose();
    _phone3Ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text   = prefs.getString('patient_name')   ?? '';
      _phone1Ctrl.text = prefs.getString('family_phone_1') ?? '';
      _phone2Ctrl.text = prefs.getString('family_phone_2') ?? '';
      _phone3Ctrl.text = prefs.getString('family_phone_3') ?? '';
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('patient_name',   _nameCtrl.text.trim());
    await prefs.setString('family_phone_1', _phone1Ctrl.text.trim());
    await prefs.setString('family_phone_2', _phone2Ctrl.text.trim());
    await prefs.setString('family_phone_3', _phone3Ctrl.text.trim());
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved!', style: TextStyle(fontSize: 16)),
          backgroundColor: Color(0xFF2E7D32),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kBlue,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const SallyLogo(width: 36, height: 36),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Settings',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Patient info ──────────────────────────────────────────────
            _sectionHeader('About Me', Icons.person_outline),
            const SizedBox(height: 12),
            _LargeField(
              controller: _nameCtrl,
              label: 'My name',
              hint: 'Enter your first name',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 28),

            // ── Device info ───────────────────────────────────────────────
            _sectionHeader('Device', Icons.devices_outlined),
            const SizedBox(height: 12),
            _InfoRow(label: 'Device ID',   value: sallyDeviceId),
            const SizedBox(height: 8),
            _InfoRow(label: 'Server',      value: sallyApiBaseUrl),
            const SizedBox(height: 28),

            // ── Family contacts ───────────────────────────────────────────
            _sectionHeader('Family Alert Contacts', Icons.family_restroom),
            const SizedBox(height: 8),
            Text(
              'If something unusual is detected, an SMS alert '
              'will be sent to these phone numbers.',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 16),
            _LargeField(
              controller: _phone1Ctrl,
              label: 'Family member 1',
              hint: '+1 (555) 000-0001',
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _LargeField(
              controller: _phone2Ctrl,
              label: 'Family member 2 (optional)',
              hint: '+1 (555) 000-0002',
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _LargeField(
              controller: _phone3Ctrl,
              label: 'Family member 3 (optional)',
              hint: '+1 (555) 000-0003',
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 32),

            // ── Save button ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 26),
                label: Text(
                  _saving ? 'Saving...' : 'Save Settings',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── SMS note ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'SMS alerts require Twilio to be configured on the server. '
                      'Contact your caregiver or administrator to enable this feature.',
                      style: TextStyle(fontSize: 14, color: Colors.amber.shade900, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: kBlue, size: 26),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kBlue),
        ),
      ],
    );
  }
}

// ── shared sub-widgets ────────────────────────────────────────────────────────

class _LargeField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboard;

  const _LargeField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboard = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 16),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 15),
        prefixIcon: Icon(icon, color: const Color(0xFF1A335D)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black54)),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 15, color: Colors.black87), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
