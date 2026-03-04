import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mobile_apps/widgets/sally_logo.dart';

// 1. Create a data model for the device
class DeviceInfo {
  final String deviceID;
  final String status;
  final int batteryLevel;

  DeviceInfo({
    required this.deviceID,
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
    // List of all mock devices that can be detected
    final allMockDevices = [
      {"deviceID": "BlueOwl 1", "signal": "90% Signal"},
      {"deviceID": "Rice Wearable v2", "signal": "75% Signal"},
      {"deviceID": "Sally's Pendant", "signal": "60% Signal"},
    ];

    // Filter out devices that are already in the _devices list
    final availableDevices = allMockDevices.where((mock) {
      return !_devices.any((d) => d.deviceID == mock["deviceID"]);
    }).toList();

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
                if (availableDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      "No new devices found.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...availableDevices.map((mock) {
                    return _buildDetectedItem(mock["deviceID"]!, mock["signal"]!);
                  }).toList(),
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

  Widget _buildDetectedItem(String deviceID, String signal) {
    return ListTile(
      leading: const Icon(Icons.bluetooth, color: Colors.blue),
      title: Text(deviceID),
      subtitle: Text(signal),
      onTap: () {
        setState(() {
          // Check if device is already added to prevent duplicates
          if (!_devices.any((d) => d.deviceID == deviceID)) {
            _devices.add(DeviceInfo(
              deviceID: deviceID,
              status: "Connected",
              batteryLevel: 100,
            ));
          }
        });
        Navigator.pop(context); // Close the dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$deviceID added successfully!")),
        );
      },
    );
  }

  void _removeDevice(DeviceInfo device) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Remove Device"),
          content: Text("Are you sure you want to remove ${device.deviceID}?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _devices.remove(device);
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("${device.deviceID} removed")),
                );
              },
              child: const Text("Yes", style: TextStyle(color: Colors.red)),
            ),
          ],
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
                      return DeviceItem(
                        device: _devices[index],
                        onRemove: () => _removeDevice(_devices[index]),
                      );
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
              onTap: _showBluetoothDialog,
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
  final VoidCallback onRemove;

  const DeviceItem({
    super.key,
    required this.device,
    required this.onRemove,
  });

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
                  device.deviceID,
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
          // More options icon with PopupMenu
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
            onSelected: (value) {
              if (value == 'remove') {
                onRemove();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'remove',
                child: Text('Remove Device', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
