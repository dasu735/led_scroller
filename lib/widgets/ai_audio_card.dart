// lib/widgets/ai_audio_card.dart
import 'package:flutter/material.dart';

class AiAudioCard extends StatefulWidget {
  const AiAudioCard({super.key});
  @override
  State<AiAudioCard> createState() => _AiAudioCardState();
}

class _AiAudioCardState extends State<AiAudioCard> {
  bool listening = false;
  bool aiInProgress = false;
  List<String> audioHistory = [];

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: aiInProgress
                      ? null
                      : () async {
                          setState(() => aiInProgress = true);
                          // call parent or backend - placeholder
                          await Future.delayed(const Duration(seconds: 1));
                          setState(() {
                            aiInProgress = false;
                            audioHistory.insert(
                              0,
                              'AI reply ${audioHistory.length + 1}',
                            );
                          });
                        },
                  child: const Text('AI'),
                ),
                ElevatedButton(onPressed: () {}, child: const Text('Browser')),
                ElevatedButton(
                  onPressed: () => setState(() => listening = !listening),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: listening ? Colors.red : null,
                  ),
                  child: Icon(listening ? Icons.mic_off : Icons.mic),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (audioHistory.isEmpty)
              const SizedBox(height: 20)
            else
              Column(
                children: audioHistory
                    .map(
                      (a) => ListTile(
                        leading: const Icon(Icons.audiotrack),
                        title: Text(a),
                        trailing: IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () {},
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}
