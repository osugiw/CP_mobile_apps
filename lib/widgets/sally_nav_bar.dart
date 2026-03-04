import 'package:flutter/material.dart';
import 'nav_item.dart';

class SallyNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const SallyNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          NavItem(
            iconPath: 'assets/images/home-4-svgrepo-com.svg',
            label: 'Home',
            isActive: currentIndex == 0,
            onTap: () => onTap(0),
          ),
          NavItem(
            iconPath: 'assets/images/pendant-with-heart-svgrepo-com.svg',
            label: 'Device',
            isActive: currentIndex == 1,
            onTap: () => onTap(1),
          ),
          NavItem(
            iconPath: 'assets/images/chat-round-svgrepo-com.svg',
            label: 'Chat',
            isActive: currentIndex == 2,
            onTap: () => onTap(2),
          ),
          NavItem(
            iconPath: 'assets/images/profile-round-1342-svgrepo-com.svg',
            label: 'Profile',
            isActive: currentIndex == 3,
            onTap: () => onTap(3),
          ),
        ],
      ),
    );
  }
}
