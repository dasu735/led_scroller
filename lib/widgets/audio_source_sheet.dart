import 'package:flutter/material.dart';

enum AudioSourceType { ai, browser, mic }
enum VoiceType { boy, girl }

class AudioSourceSheet extends StatefulWidget {
  final VoiceType? initialVoice; // Make nullable
  final ValueChanged<VoiceType>? onVoiceChanged; // Make nullable
  final ValueChanged<AudioSourceType> onSelected;

  const AudioSourceSheet({
    super.key,
    this.initialVoice,
    this.onVoiceChanged,
    required this.onSelected,
  });

  @override
  State<AudioSourceSheet> createState() => _AudioSourceSheetState();
}

class _AudioSourceSheetState extends State<AudioSourceSheet> {
  late VoiceType _voice;

  @override
  void initState() {
    super.initState();
    _voice = widget.initialVoice ?? VoiceType.girl; // Provide default
  }

  Widget _option({
    required String title,
    required String asset,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                asset, 
                height: 42,
                errorBuilder: (context, error, stackTrace) => 
                    Icon(Icons.image_not_supported, size: 42, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Get Audio By',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Options
            Row(
              children: [
                _option(
                  title: 'AI\nAssistance',
                  asset: 'assets/images/ai.png',
                  onTap: () => widget.onSelected(AudioSourceType.ai),
                ),
                const SizedBox(width: 12),
                _option(
                  title: 'Browser',
                  asset: 'assets/images/brow.png',
                  onTap: () => widget.onSelected(AudioSourceType.browser),
                ),
                const SizedBox(width: 12),
                _option(
                  title: 'Using\nMicrophone',
                  asset: 'assets/images/micro.png',
                  onTap: () => widget.onSelected(AudioSourceType.mic),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Voice selector
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _voiceButton('Boy', VoiceType.boy),
                    _voiceButton('Girl', VoiceType.girl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceButton(String label, VoiceType type) {
    final bool selected = _voice == type;
    return GestureDetector(
      onTap: () {
        setState(() => _voice = type);
        widget.onVoiceChanged?.call(type); // Safe call
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
