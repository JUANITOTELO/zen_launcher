import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class QuickNotesPage extends StatefulWidget {
  const QuickNotesPage({super.key});

  @override
  State<QuickNotesPage> createState() => _QuickNotesPageState();
}

class _QuickNotesPageState extends State<QuickNotesPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLocked = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadNote();
    _loadLockState();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadLockState() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note_locked.txt');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (mounted) {
          setState(() {
            _isLocked = content.trim() == 'true';
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading note lock state: $e");
    }
  }

  Future<void> _saveLockState(bool locked) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note_locked.txt');
      await file.writeAsString(locked ? 'true' : 'false');
    } catch (e) {
      debugPrint("Error saving note lock state: $e");
    }
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
    });
    if (_isLocked) {
      _focusNode.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
    _saveLockState(_isLocked);
  }

  Future<void> _loadNote() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note.txt');
      if (await file.exists()) {
        final text = await file.readAsString();
        if (mounted) _controller.text = text;
      }
    } catch (e) {
      debugPrint("Error loading note: $e");
    }
  }

  Future<void> _saveNote(String text) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note.txt');
      await file.writeAsString(text);
    } catch (e) {
      debugPrint("Error saving note: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "THOUGHTS",
                  style: TextStyle(
                    color: Color.fromARGB(207, 255, 255, 255),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                IconButton(
                  key: const Key('notes_lock_button'),
                  icon: Icon(
                    _isLocked ? Icons.lock_outline : Icons.lock_open_rounded,
                    size: 18,
                    color: _isLocked ? Colors.white38 : Colors.amberAccent,
                  ),
                  tooltip: _isLocked ? "Unlock notes" : "Lock notes",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                  onPressed: _toggleLock,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: TextField(
                key: const Key('notes_text_field'),
                controller: _controller,
                focusNode: _focusNode,
                readOnly: _isLocked,
                showCursor: !_isLocked,
                onChanged: _saveNote,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: _isLocked ? "Notes locked." : "Type something...",
                  hintStyle: const TextStyle(color: Colors.white24),
                ),
                cursorColor: Colors.amberAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
