// lib/widgets/rate_dialog.dart
import 'package:flutter/material.dart';

class RateDialog extends StatefulWidget {
  const RateDialog({super.key});
  @override
  State<RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<RateDialog> {
  int rating = 0;
  final TextEditingController note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rate App'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            children: List.generate(
              5,
              (i) => IconButton(
                icon: Icon(
                  i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                  color: Colors.amber,
                ),
                onPressed: () => setState(() => rating = i + 1),
              ),
            ),
          ),
          TextField(
            controller: note,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Leave note (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Thanks for rating $rating★')),
            );
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
