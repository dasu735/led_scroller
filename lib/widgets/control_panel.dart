// lib/widgets/control_panel.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

typedef VoidFileCallback = void Function(File? f);
typedef VoidColorCallback = void Function(Color c);

class ControlPanel extends StatelessWidget {
  final TextEditingController textController;
  final String displayText;
  final Color textColor;
  final Color backgroundColor;
  final double speed;
  final double textSize;
  final bool blinkText, blinkBackground;
  final bool isBusy;
  final List<String> history;
  final bool playing; // whether scroller is playing
  final bool isFavorite; // whether current text is favorited

  // callbacks (match your signatures)
  final ValueChanged<String> onTextChanged;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onTextSizeChanged;
  final ValueChanged<bool> onToggleBlinkText;
  final ValueChanged<bool> onToggleBlinkBackground;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSetDirection;
  final VoidFileCallback onPickBackgroundImage;
  final VoidColorCallback onPickTextColor;
  final VoidColorCallback onPickBackgroundColor;
  final ValueChanged<bool> onUseGradientChanged;
  final ValueChanged<bool> onUseLedDotsChanged;
  final Future<void> Function()? onShare;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onSharePng;
  final Future<void> Function()? onDownloadPng;
  final VoidCallback onOpenImagePicker;
  final ValueChanged<int> onDeleteHistoryAt;
  final ValueChanged<String> onPickHistoryItem;
  final VoidCallback onShareApp;
  final VoidCallback onToggleFavorite; // NEW

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
    required this.isBusy,
    required this.history,
    required this.playing,
    required this.isFavorite,
    required this.onTextChanged,
    required this.onSpeedChanged,
    required this.onTextSizeChanged,
    required this.onToggleBlinkText,
    required this.onToggleBlinkBackground,
    required this.onTogglePlay,
    required this.onSetDirection,
    required this.onPickBackgroundImage,
    required this.onPickTextColor,
    required this.onPickBackgroundColor,
    required this.onUseGradientChanged,
    required this.onUseLedDotsChanged,
    required this.onShare,
    required this.onDownload,
    required this.onSharePng,
    required this.onDownloadPng,
    required this.onOpenImagePicker,
    required this.onDeleteHistoryAt,
    required this.onPickHistoryItem,
    required this.onShareApp,
    required this.onToggleFavorite,
  });

  void _showColorPicker(
      BuildContext context, Color current, ValueChanged<Color> onPicked) {
    Color temp = current;
    showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            backgroundColor: Colors.black,
            title:
                const Text('Pick Color', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
                child: ColorPicker(
                    pickerColor: temp, onColorChanged: (c) => temp = c)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () {
                    onPicked(temp);
                    Navigator.pop(context);
                  },
                  child: const Text('OK'))
            ],
          );
        });
  }

  void _showHistorySheet(BuildContext context) {
    showModalBottomSheet(
        context: context,
        builder: (_) {
          return SafeArea(
              child: SizedBox(
            height: 300,
            child: Column(children: [
              const SizedBox(height: 8),
              const Text('History',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: history.isEmpty
                    ? const Center(child: Text('No history'))
                    : ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (c, i) {
                          final t = history[i];
                          return ListTile(
                            title: Text(t, overflow: TextOverflow.ellipsis),
                            leading: const Icon(Icons.history),
                            trailing: IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  onDeleteHistoryAt(i);
                                  Navigator.pop(context);
                                }),
                            onTap: () {
                              onPickHistoryItem(t);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ]),
          ));
        });
  }

  // choose readable foreground color for a background color
  Color _foregroundFor(Color bg) =>
      bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  @override
  Widget build(BuildContext context) {
    final Color active = textColor;
    final Color disabledColor = Colors.grey.shade700;
    final Color fgActive = _foregroundFor(active);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
              icon: const Icon(Icons.history, color: Colors.white),
              onPressed: () => _showHistorySheet(context)),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: textController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF373737),
                  hintText: 'Enter text...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20))),
              onChanged: (v) => onTextChanged(v),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              onPressed: onOpenImagePicker),
          const SizedBox(width: 4),
          // Star favorite button
          IconButton(
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? active : Colors.white,
            ),
            onPressed: onToggleFavorite,
          ),
          const SizedBox(width: 4),
          IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: onShareApp),
        ]),
        const SizedBox(height: 12),

        // Play controls — center icon toggles play/pause using playing flag
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Previous (left)
            _actionButton(
              context,
              icon: Icons.skip_previous,
              enabled: !isBusy,
              background: isBusy ? disabledColor : active,
              iconColor: isBusy ? Colors.white70 : fgActive,
              onPressed: () => onSetDirection(1),
            ),

            // Play/Pause (center) — shows pause when playing, play when stopped
            _actionButton(
              context,
              icon: playing ? Icons.pause : Icons.play_arrow,
              enabled: !isBusy,
              background: isBusy ? disabledColor : active,
              iconColor: isBusy ? Colors.white70 : fgActive,
              onPressed: onTogglePlay,
              large: true,
            ),

            // Next (right)
            _actionButton(
              context,
              icon: Icons.skip_next,
              enabled: !isBusy,
              background: isBusy ? disabledColor : active,
              iconColor: isBusy ? Colors.white70 : fgActive,
              onPressed: () => onSetDirection(-1),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Speed slider
        Row(children: [
          const Text('Speed', style: TextStyle(color: Colors.white)),
          Expanded(
              child: Slider(
                  activeColor: active,
                  value: speed,
                  min: 10,
                  max: 200,
                  onChanged: onSpeedChanged)),
          Text('${speed.toInt()} Px',
              style: const TextStyle(color: Colors.white)),
        ]),

        // Size slider
        Row(children: [
          const Text('Size', style: TextStyle(color: Colors.white)),
          Expanded(
              child: Slider(
                  activeColor: active,
                  value: textSize,
                  min: 20,
                  max: 200,
                  onChanged: onTextSizeChanged)),
          Text('${textSize.toInt()} Px',
              style: const TextStyle(color: Colors.white)),
        ]),

        const SizedBox(height: 8),

        // Colors row
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          const Text('Colors',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ElevatedButton(
              onPressed: () =>
                  _showColorPicker(context, textColor, onPickTextColor),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  foregroundColor: Colors.white),
              child: const Text('Text')),
          ElevatedButton(
              onPressed: () => _showColorPicker(
                  context, backgroundColor, onPickBackgroundColor),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  foregroundColor: Colors.white),
              child: const Text('Background')),
        ]),

        const SizedBox(height: 8),

        // Background toggles
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ElevatedButton(
              onPressed: () {
                onPickBackgroundImage.call(null);
                onUseGradientChanged(false);
                onUseLedDotsChanged(false);
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
              child: const Text('Solid')),
          ElevatedButton(
              onPressed: () {
                onUseGradientChanged(true);
                onPickBackgroundImage.call(null);
                onUseLedDotsChanged(false);
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
              child: const Text('Gradient')),
          ElevatedButton(
              onPressed: () {
                onUseLedDotsChanged(true);
                onPickBackgroundImage.call(null);
                onUseGradientChanged(false);
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
              child: const Text('LED')),
        ]),

        const SizedBox(height: 12),

        // Audio / blinking toggles
        Row(children: [
          Checkbox(
              value: blinkText,
              onChanged: (v) => onToggleBlinkText(v ?? false),
              activeColor: active),
          const Text('Blink Text', style: TextStyle(color: Colors.white)),
          const SizedBox(width: 12),
          Checkbox(
              value: blinkBackground,
              onChanged: (v) => onToggleBlinkBackground(v ?? false),
              activeColor: active),
          const Text('Blink Background', style: TextStyle(color: Colors.white)),
        ]),

        const SizedBox(height: 12),

        // Share / Download GIF buttons — use textColor when active
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (isBusy || onShare == null) ? null : () => onShare!(),
              icon: Icon(Icons.share,
                  color: _foregroundFor(isBusy ? disabledColor : active)),
              label: Text(isBusy ? 'Processing...' : 'Share GIF',
                  style: TextStyle(
                      color: _foregroundFor(isBusy ? disabledColor : active))),
              style: ElevatedButton.styleFrom(
                backgroundColor: isBusy ? disabledColor : active,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed:
                  (isBusy || onDownload == null) ? null : () => onDownload!(),
              icon: Icon(Icons.download,
                  color: _foregroundFor(isBusy ? disabledColor : active)),
              label: const Text('Download GIF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isBusy ? disabledColor : active,
                foregroundColor:
                    _foregroundFor(isBusy ? disabledColor : active),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),

        const SizedBox(height: 8),

        // PNG actions — smaller secondary buttons but still use textColor for accents
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          OutlinedButton.icon(
            onPressed:
                (isBusy || onSharePng == null) ? null : () => onSharePng!(),
            icon: Icon(Icons.image, color: isBusy ? disabledColor : active),
            label: Text('Share PNG',
                style: TextStyle(color: isBusy ? disabledColor : active)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: isBusy ? disabledColor : active),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            ),
          ),
          OutlinedButton.icon(
            onPressed: (isBusy || onDownloadPng == null)
                ? null
                : () => onDownloadPng!(),
            icon: Icon(Icons.save, color: isBusy ? disabledColor : active),
            label: Text('Save PNG',
                style: TextStyle(color: isBusy ? disabledColor : active)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: isBusy ? disabledColor : active),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            ),
          ),
        ]),
      ]),
    );
  }

  // Helper builder for the play/action buttons to keep a uniform look
  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required bool enabled,
    required Color background,
    required Color iconColor,
    required VoidCallback? onPressed,
    bool large = false,
  }) {
    final double size = large ? 56 : 46;
    final double iconSize = large ? 28 : 20;
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? background : Colors.grey.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: EdgeInsets.zero,
          elevation: 0,
        ),
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}
