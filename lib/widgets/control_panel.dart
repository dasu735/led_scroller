// lib/widgets/control_panel.dart
import 'dart:io';
import 'package:flutter/material.dart';

typedef VoidAsyncCallback = Future<void> Function();

class ControlPanel extends StatelessWidget {
  final TextEditingController textController;
  final String displayText;
  final Color textColor;
  final Color backgroundColor;
  final double speed;
  final double textSize;
  final bool blinkText;
  final bool blinkBackground;
  final bool isBusy;

  // Callbacks
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<double>? onSpeedChanged;
  final ValueChanged<double>? onTextSizeChanged;
  final ValueChanged<bool>? onToggleBlinkText;
  final ValueChanged<bool>? onToggleBlinkBackground;
  final VoidCallback? onTogglePlay;
  final ValueChanged<int>? onSetDirection;
  final VoidCallback? onPickBackgroundImage;
  final ValueChanged<Color>? onPickTextColor;
  final ValueChanged<Color>? onPickBackgroundColor;
  final ValueChanged<bool>? onUseGradientChanged;
  final ValueChanged<bool>? onUseLedDotsChanged;

  // Async share / download callbacks
  final VoidAsyncCallback? onShare; // share GIF
  final VoidAsyncCallback? onDownload; // save GIF
  final VoidAsyncCallback? onSharePng; // share PNG snapshot
  final VoidAsyncCallback? onDownloadPng; // save PNG snapshot

  const ControlPanel({
    super.key,
    required this.textController,
    required this.displayText,
    required this.textColor,
    required this.backgroundColor,
    required this.speed,
    required this.textSize,
    required this.blinkText,
    required this.blinkBackground,
    this.isBusy = false,
    this.onTextChanged,
    this.onSpeedChanged,
    this.onTextSizeChanged,
    this.onToggleBlinkText,
    this.onToggleBlinkBackground,
    this.onTogglePlay,
    this.onSetDirection,
    this.onPickBackgroundImage,
    this.onPickTextColor,
    this.onPickBackgroundColor,
    this.onUseGradientChanged,
    this.onUseLedDotsChanged,
    this.onShare,
    this.onDownload,
    this.onSharePng,
    this.onDownloadPng,
  });

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidAsyncCallback? onTap,
    bool enabled = true,
  }) {
    return SizedBox(
      height: 40,
      width: 140,
      child: ElevatedButton.icon(
        onPressed:
            (!enabled || onTap == null) ? null : () async => await onTap(),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: textController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color.fromARGB(255, 55, 55, 55),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20)),
                    hintText: "Enter text...",
                    hintStyle: const TextStyle(color: Colors.grey),
                  ),
                  onChanged: (v) {
                    if (onTextChanged != null) onTextChanged!(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                  icon: const Icon(Icons.photo, color: Colors.white),
                  onPressed: onPickBackgroundImage),
            ],
          ),
          const SizedBox(height: 12),

          // Play/Direction
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                  onPressed: () => onSetDirection?.call(1),
                  icon: const Icon(Icons.play_arrow, color: Colors.white)),
              IconButton(
                  onPressed: onTogglePlay,
                  icon: const Icon(Icons.pause, color: Colors.white)),
              IconButton(
                  onPressed: () => onSetDirection?.call(-1),
                  icon: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(3.1416),
                      child:
                          const Icon(Icons.play_arrow, color: Colors.white))),
            ],
          ),
          const SizedBox(height: 8),

          // Speed slider
          Row(
            children: [
              const Text('Speed', style: TextStyle(color: Colors.white)),
              Expanded(
                  child: Slider(
                      value: speed,
                      min: 10,
                      max: 200,
                      onChanged: (v) {
                        if (onSpeedChanged != null) onSpeedChanged!(v);
                      })),
              Text('${speed.toInt()}',
                  style: const TextStyle(color: Colors.white)),
            ],
          ),

          // Size slider
          Row(
            children: [
              const Text('Size', style: TextStyle(color: Colors.white)),
              Expanded(
                  child: Slider(
                      value: textSize,
                      min: 20,
                      max: 200,
                      onChanged: (v) {
                        if (onTextSizeChanged != null) onTextSizeChanged!(v);
                      })),
              Text('${textSize.toInt()}',
                  style: const TextStyle(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 8),

          // Blink toggles
          Row(
            children: [
              Checkbox(
                  value: blinkText,
                  onChanged: (v) {
                    if (onToggleBlinkText != null)
                      onToggleBlinkText!(v ?? false);
                  }),
              const Text('Blink Text', style: TextStyle(color: Colors.white)),
              const SizedBox(width: 16),
              Checkbox(
                  value: blinkBackground,
                  onChanged: (v) {
                    if (onToggleBlinkBackground != null)
                      onToggleBlinkBackground!(v ?? false);
                  }),
              const Text('Blink Background',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),

          // Share / Download (PNG + GIF)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(
                  label: 'Share PNG',
                  icon: Icons.image,
                  onTap: onSharePng,
                  enabled: !isBusy && onSharePng != null),
              _actionButton(
                  label: 'Save PNG',
                  icon: Icons.download,
                  onTap: onDownloadPng,
                  enabled: !isBusy && onDownloadPng != null),
              _actionButton(
                  label: 'Share GIF',
                  icon: Icons.gif,
                  onTap: onShare,
                  enabled: !isBusy && onShare != null),
              _actionButton(
                  label: 'Save GIF',
                  icon: Icons.save_alt,
                  onTap: onDownload,
                  enabled: !isBusy && onDownload != null),
            ],
          ),
        ],
      ),
    );
  }
}
