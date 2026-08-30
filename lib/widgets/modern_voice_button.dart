import 'package:flutter/material.dart';

class ModernVoiceButton extends StatefulWidget {
  final bool isListening;
  final bool isProcessing;
  final VoidCallback onTap;

  const ModernVoiceButton({
    super.key,
    required this.isListening,
    required this.isProcessing,
    required this.onTap,
  });

  @override
  State<ModernVoiceButton> createState() => _ModernVoiceButtonState();
}

class _ModernVoiceButtonState extends State<ModernVoiceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color buttonColor = const Color(0xFF10B981);
    String buttonText = "แตะเพื่อพูด";
    IconData buttonIcon = Icons.mic_rounded;

    if (widget.isListening) {
      buttonColor = const Color(0xFFEF4444);
      buttonText = "กำลังฟัง...";
      buttonIcon = Icons.mic_rounded;
    } else if (widget.isProcessing) {
      buttonColor = const Color(0xFFF59E0B);
      buttonText = "กำลังวิเคราะห์...";
      buttonIcon = Icons.auto_awesome_rounded;
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple Pulsing Effect
          if (widget.isListening)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  width: 220 + (_controller.value * 40),
                  height: 220 + (_controller.value * 40),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(
                      0xFFEF4444,
                    ).withOpacity(0.3 * (1 - _controller.value)),
                  ),
                );
              },
            ),

          // Main Glassmorphic Circle Button
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [buttonColor.withOpacity(0.85), buttonColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withOpacity(0.4),
                  blurRadius: 25,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment
                  .center, // ✅ แก้ไขตรงนี้เป็น MainAxisAlignment.center แล้วครับ
              children: [
                Icon(buttonIcon, size: 64, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  buttonText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
