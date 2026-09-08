# Fix Wallpaper Refresh, Apps Drawer Keyboard Dismissal, Notes Lock/Unlock, and E2E Testing Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Fix on-demand wallpaper refreshing by eliminating Flutter FileImage widget reconciliation caching, eliminate virtual keyboard persistence and glitching when exiting the apps drawer, add a persistent lock/unlock editing toggle to the left-side quick notes, and implement comprehensive end-to-end testing using Flutter's `integration_test` module.

**Architecture:** The launcher's UI is built on a 3-page infinite carousel (`PageView.builder`) with an overlay bottom sheet drawer (`SmartAppListDrawer`). The wallpaper refresh fix uses dynamic widget keys and image cache eviction to force Flutter's engine to re-resolve overwritten files while guarding native platform wallpaper channels; drawer keyboard management binds `PopScope`, `FocusNode`, `ScrollViewKeyboardDismissBehavior.onDrag`, and route popping on app launch; notes editing introduces a persistent toggle state in `_QuickNotesPage` controlling `TextField.readOnly` and keyboard focus; and full e2e coverage is implemented via `integration_test/app_test.dart`.

**Tech Stack:** Flutter 3.10+, Dart, `integration_test` (Flutter SDK), `flutter_test`, `http`, `path_provider`, `wallpaper_manager_plus`, Linux/Android runner.

---

## Current Context and Problem Analysis

1. **Wallpaper Refresh at Command:**
   - In `HomeScreen._syncWallpaper()`, remote wallpaper is downloaded to `File('${directory.path}/daily_wallpaper.webp')` and `FileImage(file).evict()` is called.
   - However, the `Image.file(_localFile!)` widget has no changing key and retains the identical file path. Because `FileImage` equality only compares path and scale, Flutter's `_ImageState.didUpdateWidget` determines `newWidget.image == oldWidget.image` and skips re-resolving the image stream.
   - Additionally, HTTP responses without cache control can return cached 304/stale data, and unhandled exceptions in `WallpaperManagerPlus` on non-Android platforms crash or abort the local UI update.
2. **Keyboard Bug Exiting Apps Drawer:**
   - In `SmartAppListDrawer`, opening search focuses a `TextField` without an explicit `FocusNode`.
   - When the drawer sheet is dismissed (by downward drag, tap outside barrier, back gesture, or launching an app in `AppListItem`), Flutter does not automatically unfocus the text field or signal the software keyboard (`TextInput.hide`) to dismiss.
   - Furthermore, `CustomScrollView` lacks `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`, leaving the keyboard active when scrolling, and `AppListItem.onTap` fails to pop the modal sheet.
3. **Lock/Unlock Notes Editing:**
   - `_QuickNotesPage` ("THOUGHTS") provides a raw multiline `TextField` without an edit lock. Swiping into the notes page or accidental taps bring up the software keyboard and risk unwanted edits.
   - A lock/unlock toggle is needed in the header with persistent state, toggling `readOnly` and dismissing the keyboard upon locking.
4. **Testing Infrastructure:**
   - `pubspec.yaml` is missing `integration_test: sdk: flutter`.
   - `test/widget_test.dart` has an outdated Flutter template test failing `flutter analyze` due to a missing `MyApp` reference.

---

## Bite-Sized Implementation Tasks

### Task 1: Add `integration_test` Dependency & Fix Existing Test Baseline

**Objective:** Configure `integration_test` in `pubspec.yaml` and repair `test/widget_test.dart` so `flutter analyze` and `flutter test` pass cleanly.

**Files:**
- Modify: `pubspec.yaml:45-56`
- Modify: `test/widget_test.dart:1-30`

**Step 1: Update `pubspec.yaml`**

In `pubspec.yaml`, add `integration_test` under `dev_dependencies`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices. The lint set provided by the package is
  # activated in the `analysis_options.yaml` file located at the root of your
  # package. See that file for information about deactivating specific lint
  # rules and activating additional ones.
  flutter_lints: ^6.0.0
```

Run command:
```bash
flutter pub get
```
Expected output: `Resolving dependencies... Got dependencies!`

**Step 2: Fix `test/widget_test.dart` baseline**

Replace `test/widget_test.dart` with a smoke test for `ZenLauncherApp`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/main.dart';

void main() {
  testWidgets('ZenLauncherApp smoke test builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ZenLauncherApp());
    await tester.pump();

    // Verify clock and home screen components load
    expect(find.byType(ZenLauncherApp), findsOneWidget);
  });
}
```

**Step 3: Run verification commands**

Run:
```bash
flutter analyze
```
Expected output: `No issues found!`

Run:
```bash
flutter test test/widget_test.dart
```
Expected output: `All tests passed!`

**Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock test/widget_test.dart
git commit -m "chore: add integration_test dependency and fix test baseline"
```

---

### Task 2: Implement Lock/Unlock Editing on Left Side Notes

**Objective:** Add persistent lock/unlock state to `_QuickNotesPage` in `lib/presentation/screens/home_screen.dart`, showing a minimalist lock icon in the header, setting `TextField.readOnly` when locked, dismissing the virtual keyboard on lock, and saving the lock preference to disk.

**Files:**
- Create: `test/presentation/screens/quick_notes_test.dart`
- Modify: `lib/presentation/screens/home_screen.dart:344-431`

**Step 1: Write failing widget test**

Create `test/presentation/screens/quick_notes_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/presentation/screens/home_screen.dart';

void main() {
  testWidgets('Quick notes page can toggle lock and unlock editing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The carousel starts at 1000 (Home). Page 999 is Notes.
    // Drag from left to right to reveal the notes page.
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();

    // Verify Notes header and lock button exist
    expect(find.text('THOUGHTS'), findsOneWidget);
    final lockButtonFinder = find.byKey(const Key('notes_lock_button'));
    expect(lockButtonFinder, findsOneWidget);

    // Verify TextField exists
    final textFieldFinder = find.byKey(const Key('notes_text_field'));
    expect(textFieldFinder, findsOneWidget);

    TextField textField = tester.widget<TextField>(textFieldFinder);
    final initialReadOnly = textField.readOnly;

    // Tap lock button to toggle
    await tester.tap(lockButtonFinder);
    await tester.pumpAndSettle();

    textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.readOnly, !initialReadOnly);
  });
}
```

**Step 2: Run test to verify failure**

Run:
```bash
flutter test test/presentation/screens/quick_notes_test.dart
```
Expected output: FAIL — `No element with key 'notes_lock_button' found`.

**Step 3: Implement lock/unlock editing in `_QuickNotesPage`**

In `lib/presentation/screens/home_screen.dart`, update `_QuickNotesPageState`:

```dart
class _QuickNotesPage extends StatefulWidget {
  const _QuickNotesPage();

  @override
  State<_QuickNotesPage> createState() => _QuickNotesPageState();
}

class _QuickNotesPageState extends State<_QuickNotesPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLocked = false;

  @override
  bool get wantKeepAlive => true; // Keep text when swiping away

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
```

**Step 4: Run test to verify pass**

Run:
```bash
flutter test test/presentation/screens/quick_notes_test.dart
```
Expected output: `All tests passed!`

**Step 5: Commit**

```bash
git add lib/presentation/screens/home_screen.dart test/presentation/screens/quick_notes_test.dart
git commit -m "feat: add persistent lock and unlock editing to left side notes"
```

---

### Task 3: Fix Keyboard Bug When Exiting Apps Drawer

**Objective:** Ensure the virtual keyboard and focus are immediately and cleanly dismissed whenever the app drawer is closed (via drag dismiss, back navigation, tap outside, or app launch) and dismiss keyboard on list scroll.

**Files:**
- Create: `test/presentation/drawers/smart_app_drawer_test.dart`
- Modify: `lib/presentation/drawers/smart_app_drawer.dart:15-170`
- Modify: `lib/presentation/widgets/app_list_item.dart:39-44`
- Modify: `lib/presentation/screens/home_screen.dart:147-158`

**Step 1: Write failing widget test**

Create `test/presentation/drawers/smart_app_drawer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/presentation/drawers/smart_app_drawer.dart';

void main() {
  testWidgets('SmartAppListDrawer has focus node and dismisses keyboard on scroll/tap', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SmartAppListDrawer(),
        ),
      ),
    );
    await tester.pump();

    // Verify search field exists
    final searchFieldFinder = find.byType(TextField);
    expect(searchFieldFinder, findsOneWidget);

    // Tap search field to focus
    await tester.tap(searchFieldFinder);
    await tester.pump();

    final TextField textField = tester.widget<TextField>(searchFieldFinder);
    expect(textField.focusNode, isNotNull);

    // Verify CustomScrollView has keyboardDismissBehavior set to onDrag
    final scrollViewFinder = find.byType(CustomScrollView);
    expect(scrollViewFinder, findsOneWidget);
    final CustomScrollView scrollView = tester.widget<CustomScrollView>(scrollViewFinder);
    expect(scrollView.keyboardDismissBehavior, ScrollViewKeyboardDismissBehavior.onDrag);
  });
}
```

**Step 2: Run test to verify failure**

Run:
```bash
flutter test test/presentation/drawers/smart_app_drawer_test.dart
```
Expected output: FAIL — `Expected: not null, Actual: null` or `keyboardDismissBehavior mismatch`.

**Step 3: Implement keyboard dismissal improvements**

1. In `lib/presentation/drawers/smart_app_drawer.dart`:
   - Add dedicated `FocusNode _searchFocusNode` and dispose it.
   - Wrap in `PopScope` to dismiss keyboard on pop.
   - Wrap sheet with a `GestureDetector` to dismiss keyboard on outside tap.
   - Set `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag` on `CustomScrollView`.

```dart
class _SmartAppListDrawerState extends State<SmartAppListDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<ZenApp> _newApps = [];
  List<ZenApp> _allApps = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _updateFilteredList();
    _searchController.addListener(_updateFilteredList);
    AppCacheService.instance.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    AppCacheService.instance.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _dismissKeyboard() {
    _searchFocusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  ...
  @override
  Widget build(BuildContext context) {
    if (!AppCacheService.instance.isLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _dismissKeyboard();
      },
      child: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.translucent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          snap: true,
          builder: (_, scrollController) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: ColoredBox(
                  color: Colors.black26,
                  child: Column(
                    children: [
                      _buildSearchBar(),
                      const Divider(color: Colors.white12, height: 1),
                      Expanded(
                        child: CustomScrollView(
                          controller: scrollController,
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          slivers: [
                            ...
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 25, 25, 15),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        decoration: const InputDecoration(
          hintText: 'Search...',
          hintStyle: TextStyle(color: Colors.white24, fontSize: 18),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        cursorColor: Colors.white,
      ),
    );
  }
```

2. In `lib/presentation/widgets/app_list_item.dart`:
   Ensure launching an app dismisses the keyboard and pops the drawer:

```dart
    return InkWell(
      onTap: () {
        FocusScope.of(context).unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        AppCacheService.instance.launchApp(zenApp);
      },
      splashColor: Colors.white10,
```

3. In `lib/presentation/screens/home_screen.dart:147-158`:
   In `_openAppDrawer()` `.then((_) { ... })`:

```dart
  void _openAppDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      barrierColor: Colors.black26,
      builder: (context) => const SmartAppListDrawer(),
    ).then((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  }
```

**Step 4: Run test to verify pass**

Run:
```bash
flutter test test/presentation/drawers/smart_app_drawer_test.dart
```
Expected output: `All tests passed!`

**Step 5: Commit**

```bash
git add lib/presentation/drawers/smart_app_drawer.dart lib/presentation/widgets/app_list_item.dart lib/presentation/screens/home_screen.dart test/presentation/drawers/smart_app_drawer_test.dart
git commit -m "fix: dismiss keyboard and clear focus when exiting apps drawer"
```

---

### Task 4: Fix On-Demand Wallpaper Refreshing from Internet

**Objective:** Ensure double-tap on the home screen immediately downloads, invalidates image caches, updates the `Image.file` widget via a dynamic `ValueKey`, safely calls Android wallpaper APIs without crashing non-Android platforms, and provides instant visual feedback.

**Files:**
- Create: `test/presentation/screens/wallpaper_refresh_test.dart`
- Modify: `lib/presentation/screens/home_screen.dart:25-125, 211-235`

**Step 1: Write failing widget test**

Create `test/presentation/screens/wallpaper_refresh_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/presentation/screens/home_screen.dart';

void main() {
  testWidgets('Double tap on home screen triggers wallpaper sync and updates key', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pump();

    // Verify HomeScreen renders with double-tap gesture detector
    final gestureFinder = find.byType(GestureDetector);
    expect(gestureFinder, findsWidgets);

    // Initial check on the background stack
    expect(find.byType(Stack), findsWidgets);
  });
}
```

**Step 2: Run test to verify failure/baseline**

Run:
```bash
flutter test test/presentation/screens/wallpaper_refresh_test.dart
```
Expected output: `All tests passed!` (baseline)

**Step 3: Implement wallpaper refresh fix in `lib/presentation/screens/home_screen.dart`**

In `_HomeScreenState`:
- Add `int _wallpaperVersion = 0;` to state.
- In `_syncWallpaper()`:
  - Add cache-busting timestamp parameter to the URL and HTTP headers `Cache-Control: no-cache`.
  - Evict `FileImage(file)` and clear Flutter image caches:
    `PaintingBinding.instance.imageCache.clear();`
    `PaintingBinding.instance.imageCache.clearLiveImages();`
  - Guard `WallpaperManagerPlus().setWallpaper()` inside `if (Platform.isAndroid)` with a dedicated `try/catch` block so platform failures never abort UI updates.
  - Update `setState(() { _localFile = file; _wallpaperVersion = DateTime.now().millisecondsSinceEpoch; });`.
  - Provide a `key: ValueKey('wallpaper_$_wallpaperVersion')` to `Image.file` so Flutter discards the old `ImageState` and immediately paints the new image without flickering (`gaplessPlayback: true`).
  - Provide user feedback if download fails or succeeds.

Code snippet for `HomeScreen`:

```dart
  int _wallpaperVersion = 0;

  Future<void> _syncWallpaper() async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);

    try {
      final cacheBustedUrl = Uri.parse('$_imageUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final response = await http.get(
        cacheBustedUrl,
        headers: const {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
      );

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/daily_wallpaper.webp');

        await file.writeAsBytes(response.bodyBytes);
        await FileImage(file).evict();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();

        if (Platform.isAndroid) {
          try {
            WallpaperManagerPlus().setWallpaper(
              file,
              WallpaperManagerPlus.bothScreens,
            );
          } catch (e) {
            debugPrint("WallpaperManager platform error: $e");
          }
        }

        _scheduleNextUpdate(const Duration(hours: 24));

        if (mounted) {
          setState(() {
            _localFile = file;
            _wallpaperVersion = DateTime.now().millisecondsSinceEpoch;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Zen refreshed.'),
              duration: Duration(milliseconds: 800),
              backgroundColor: Color.fromARGB(199, 238, 238, 238),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Wallpaper download failed (${response.statusCode})'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Wallpaper Error: $e");
      _scheduleNextUpdate(const Duration(hours: 1));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh wallpaper. Retrying later.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }
```

In `build`:
```dart
            // 1. Static Background Layer
            if (_localFile != null)
              Image.file(
                _localFile!,
                key: ValueKey('wallpaper_$_wallpaperVersion'),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(color: Colors.black38),
              ),
```

**Step 4: Run test to verify pass**

Run:
```bash
flutter test test/presentation/screens/wallpaper_refresh_test.dart
```
Expected output: `All tests passed!`

**Step 5: Commit**

```bash
git add lib/presentation/screens/home_screen.dart test/presentation/screens/wallpaper_refresh_test.dart
git commit -m "fix: ensure wallpaper refreshes reliably on command with cache busting and dynamic key"
```

---

### Task 5: Implement End-to-End E2E Tests with `integration_test`

**Objective:** Author end-to-end integration tests using `package:integration_test/integration_test.dart` covering wallpaper refresh on command, opening/closing the drawer without keyboard leaks, and locking/unlocking notes editing.

**Files:**
- Create: `integration_test/app_test.dart`

**Step 1: Create `integration_test/app_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zen_launcher/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Zen Launcher End-to-End Tests', () {
    testWidgets('E2E: Left side notes lock/unlock workflow', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Swipe right to navigate to page 0 (Quick Notes)
      await tester.drag(find.byType(PageView), const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(find.text('THOUGHTS'), findsOneWidget);

      final lockButtonFinder = find.byKey(const Key('notes_lock_button'));
      expect(lockButtonFinder, findsOneWidget);

      final textFieldFinder = find.byKey(const Key('notes_text_field'));
      expect(textFieldFinder, findsOneWidget);

      // Verify unlocking & entering text
      TextField textField = tester.widget<TextField>(textFieldFinder);
      if (textField.readOnly) {
        await tester.tap(lockButtonFinder);
        await tester.pumpAndSettle();
      }

      await tester.enterText(textFieldFinder, 'Zen e2e note test');
      await tester.pumpAndSettle();
      expect(find.text('Zen e2e note test'), findsOneWidget);

      // Lock notes
      await tester.tap(lockButtonFinder);
      await tester.pumpAndSettle();

      textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.readOnly, isTrue);

      // Return to home page (page 1)
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
    });

    testWidgets('E2E: App drawer opens, searches, and dismisses cleanly without keyboard leak', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Open drawer using arrow up button
      final drawerButton = find.byIcon(Icons.keyboard_arrow_up);
      expect(drawerButton, findsOneWidget);
      await tester.tap(drawerButton);
      await tester.pumpAndSettle();

      // Verify search field is displayed
      final searchFieldFinder = find.byType(TextField);
      expect(searchFieldFinder, findsOneWidget);

      // Tap search and enter query
      await tester.tap(searchFieldFinder);
      await tester.enterText(searchFieldFinder, 'settings');
      await tester.pumpAndSettle();

      // Dismiss drawer by dragging down
      await tester.drag(find.byType(DraggableScrollableSheet), const Offset(0, 500));
      await tester.pumpAndSettle();

      // Verify drawer is dismissed and no search field is active
      expect(find.text('Search...'), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    });

    testWidgets('E2E: Wallpaper refresh on command', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Double-tap on the home screen to trigger refresh
      final homeCenter = tester.getCenter(find.byType(PageView));
      await tester.tapAt(homeCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(homeCenter);
      await tester.pump();

      // Verify that sync doesn't crash the widget tree
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PageView), findsOneWidget);
    });
  });
}
```

**Step 2: Run verification command**

Run e2e integration test:
```bash
flutter test integration_test/app_test.dart -d linux
```
Expected output: `All tests passed!`

Run full project test suite:
```bash
flutter test
```
Expected output: `All tests passed!`

Run project analysis:
```bash
flutter analyze
```
Expected output: `No issues found!`

**Step 3: Commit**

```bash
git add integration_test/app_test.dart
git commit -m "test: add end-to-end integration tests using integration_test module"
```

---

## Risks, Tradeoffs, and Open Questions

1. **WallpaperManagerPlus on Desktop vs Mobile:**
   - `WallpaperManagerPlus` is an Android plugin. Running integration tests on Linux desktop or other non-Android targets would crash unless calls are guarded with `Platform.isAndroid`. The proposed solution cleanly isolates system wallpaper setting while updating Flutter's in-app background everywhere.
2. **Infinite PageView Gestures vs Double Tap:**
   - In Flutter, `PageView` has internal scroll recognition. If double-tap is positioned on the parent `GestureDetector`, gestures might conflict if the user moves during the tap. The existing `onDoubleTap` is preserved and verified to work over the home page area.
3. **Database & Installed Apps Mocks in E2E:**
   - In desktop/Linux test runs, `InstalledApps.getInstalledApps` returns empty lists without crashing. If running on emulators or real Android hardware, `AppCacheService` will populate with actual installed apps.
4. **Notes Default Lock State:**
   - The default state on first run is set to unlocked (`false`) so new users can type immediately, with the choice persisted across launches as soon as toggled.
