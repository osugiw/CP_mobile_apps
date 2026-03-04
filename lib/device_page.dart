import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mobile_apps/widgets/sally_logo.dart';

// 1. Create a data model for the device
class DeviceInfo {
  final String name;
  final String status;
  final int batteryLevel;

  DeviceInfo({
    required this.name,
    this.status = "Connected",
    this.batteryLevel = 100,
  });
}

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  // 2. List of DeviceInfo objects
  final List<DeviceInfo> _devices = [];

  // This replaces the old dummy auto-add logic
  void _showBluetoothDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            "Detecting Devices...",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 20),
                // Mock list of detected Bluetooth devices
                _buildDetectedItem("BlueOwl 1", "90% Signal"),
                _buildDetectedItem("Rice Wearable v2", "75% Signal"),
                _buildDetectedItem("Sally's Pendant", "60% Signal"),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetectedItem(String name, String signal) {
    return ListTile(
      leading: const Icon(Icons.bluetooth, color: Colors.blue),
      title: Text(name),
      subtitle: Text(signal),
      onTap: () {
        setState(() {
          // Check if device is already added to prevent duplicates
          if (!_devices.any((d) => d.name == name)) {
            _devices.add(DeviceInfo(
              name: name,
              status: "Connected",
              batteryLevel: 100,
            ));
          }
        });
        Navigator.pop(context); // Close the dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$name added successfully!")),
        );
      },
    );
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
                  'Devices',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40),
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
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: _devices.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      return DeviceItem(device: _devices[index]);
                    },
                  ),
                ),
                if (_devices.isEmpty)
                  Center(
                    child: Text(
                      "All paired devices will be shown in here",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: GestureDetector(
              onTap: _showBluetoothDialog, // Changed from _addDevices
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/images/bluetooth-circle-svgrepo-com.svg',
                      width: 40,
                      height: 40,
                      colorFilter: const ColorFilter.mode(
                        Colors.blue,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Add Device',
                      style: TextStyle(
                        color: logoBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DeviceItem extends StatelessWidget {
  final DeviceInfo device;

  const DeviceItem({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    const Color cardBlue = Color(0xFFE8EEF8);
    const Color logoBlue = Color(0xFF1A335D);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBlue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Device Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: SvgPicture.asset(
              'assets/images/pendant-with-heart-svgrepo-com.svg',
              width: 40,
              height: 40,
              colorFilter: const ColorFilter.mode(logoBlue, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: 16),
          // Device Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                Text(
                  "Status: ${device.status}",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SvgPicture.asset(
                      'assets/images/battery-half-svgrepo-com.svg',
                      width: 24,
                      height: 12,
                      colorFilter: ColorFilter.mode(
                        device.batteryLevel > 20 ? Colors.lightGreen : Colors.red,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "${device.batteryLevel}%",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // More options icon
          Icon(Icons.more_vert, color: Colors.grey.shade400),
        ],
      ),
    );
  }
}
