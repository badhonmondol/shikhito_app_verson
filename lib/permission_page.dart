import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionPage extends StatefulWidget {
  final VoidCallback onAllGranted;
  const PermissionPage({super.key, required this.onAllGranted});

  @override
  State<PermissionPage> createState() => _PermissionPageState();
}

class _PermissionPageState extends State<PermissionPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  bool _micGranted = false;
  bool _locGranted = false;
  bool _phoneGranted = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
    _checkCurrentStatus();
  }

  Future<void> _checkCurrentStatus() async {
    final mic = await Permission.microphone.status;
    final loc = await Permission.location.status;
    final phone = await Permission.phone.status;
    setState(() {
      _micGranted = mic.isGranted;
      _locGranted = loc.isGranted;
      _phoneGranted = phone.isGranted;
    });
    if (_micGranted && _locGranted && _phoneGranted) widget.onAllGranted();
  }

  Future<void> _requestPermissions() async {
    setState(() => _isChecking = true);
    final mic = await Permission.microphone.request();
    final loc = await Permission.location.request();
    final phone = await Permission.phone.request();
    setState(() {
      _micGranted = mic.isGranted;
      _locGranted = loc.isGranted;
      _phoneGranted = phone.isGranted;
      _isChecking = false;
    });

    if (_micGranted && _locGranted && _phoneGranted) {
      await Future.delayed(const Duration(milliseconds: 500));
      widget.onAllGranted();
    } else {
      final isPermanent =
          await Permission.microphone.isPermanentlyDenied ||
          await Permission.location.isPermanentlyDenied ||
          await Permission.phone.isPermanentlyDenied;
      if (isPermanent && mounted) _showSettingsDialog();
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('অনুমতি দরকার'),
        content: const Text(
          'মাইক্রোফোন অনুমতি দিতে Settings এ যান।\n\n'
          'Settings → Apps → শিখিতো → Permissions → Microphone → Allow',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বাতিল'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
            ),
            child: const Text(
              'Settings খুলুন',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allGranted = _micGranted && _locGranted && _phoneGranted;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF3B82F6), Color(0xFF06B6D4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            // ✅ FIX 1: SingleChildScrollView দিয়ে overflow ঠিক করা
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                // ✅ FIX 2: Screen height এর সমান minimum height দেওয়া
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // --- Top Icon ---
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.security_rounded,
                          color: Colors.white,
                          size: 52,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // --- Title ---
                      const Text(
                        'অনুমতি দরকার',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'অ্যাপটি ব্যবহার করতে নিচের\nঅনুমতি দিতে হবে।',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // --- Permission Cards ---
                      _buildPermissionCard(
                        icon: Icons.mic_rounded,
                        title: 'মাইক্রোফোন',
                        desc: 'কথা বলে বাংলায় লেখার জন্য',
                        granted: _micGranted,
                        color: const Color(0xFFFF6584),
                      ),
                      const SizedBox(height: 14),
                      _buildPermissionCard(
                        icon: Icons.location_on,
                        title: 'অবস্থান (Location)',
                        desc: 'ঠিকানা/লোকেশন আপডেট করার জন্য',
                        granted: _locGranted,
                        color: const Color(0xFF06B6D4),
                      ),
                      const SizedBox(height: 14),
                      _buildPermissionCard(
                        icon: Icons.sim_card,
                        title: 'ফোন নম্বর (Phone)',
                        desc: 'ডিভাইসের সিম নম্বর অটোমেটিক আপডেটের জন্য',
                        granted: _phoneGranted,
                        color: const Color(0xFF9C88FF),
                      ),

                      // ✅ FIX 3: Spacer দিয়ে button কে নিচে push করা
                      const Spacer(),
                      const SizedBox(height: 32),

                      // --- Button ---
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: _isChecking ? null : _requestPermissions,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              color: allGranted
                                  ? Colors.green.shade400
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 15,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isChecking
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Color(0xFF6C63FF),
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          allGranted
                                              ? Icons.check_circle_rounded
                                              : Icons.lock_open_rounded,
                                          color: allGranted
                                              ? Colors.white
                                              : const Color(0xFF6C63FF),
                                          size: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          allGranted
                                              ? 'অনুমতি দেওয়া হয়েছে ✓'
                                              : 'অনুমতি দিন',
                                          style: TextStyle(
                                            color: allGranted
                                                ? Colors.white
                                                : const Color(0xFF6C63FF),
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String desc,
    required bool granted,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: granted
                  ? Colors.green.withValues(alpha: 0.3)
                  : color.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              granted ? Icons.check_rounded : icon,
              color: granted ? Colors.greenAccent : Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: granted
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              granted ? 'দেওয়া আছে' : 'দরকার',
              style: TextStyle(
                color: granted ? Colors.greenAccent : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}