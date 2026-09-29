import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/app_cache_service.dart';

enum PinMode { setup, verify, changePin }

class PinAuthDialog extends StatefulWidget {
  final void Function(BuildContext context) onSuccess;
  final PinMode initialMode;

  const PinAuthDialog({
    super.key,
    required this.onSuccess,
    this.initialMode = PinMode.verify,
  });

  static Future<void> show({
    required BuildContext context,
    required void Function(BuildContext context) onSuccess,
    PinMode initialMode = PinMode.verify,
  }) async {
    final hasPin = await AppCacheService.instance.hasPin();
    if (!context.mounted) return;

    final authenticated = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => PinAuthDialog(
        initialMode: hasPin ? initialMode : PinMode.setup,
        onSuccess: (dialogContext) {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop(true);
          }
        },
      ),
    );

    if (authenticated == true && context.mounted) {
      onSuccess(context);
    }
  }

  @override
  State<PinAuthDialog> createState() => _PinAuthDialogState();
}

class _PinAuthDialogState extends State<PinAuthDialog> {
  late PinMode _mode;
  String _enteredPin = '';
  String? _firstEnteredPin;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  String get _title {
    if (_mode == PinMode.setup) {
      return _firstEnteredPin == null ? 'CREATE 4-DIGIT PIN' : 'CONFIRM PIN';
    } else if (_mode == PinMode.changePin) {
      return 'ENTER CURRENT PIN';
    }
    return 'ENTER 4-DIGIT PIN';
  }

  String get _subtitle {
    if (_mode == PinMode.setup) {
      return _firstEnteredPin == null
          ? 'Secure your hidden apps vault'
          : 'Re-enter your 4-digit PIN to confirm';
    }
    return 'Unlock your hidden apps vault';
  }

  void _onDigitPressed(int digit) {
    if (_enteredPin.length >= 4 || _isLoading) return;
    HapticFeedback.lightImpact();

    setState(() {
      _errorMessage = null;
      _enteredPin += digit.toString();
    });

    if (_enteredPin.length == 4) {
      _handlePinCompleted();
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isEmpty || _isLoading) return;
    HapticFeedback.lightImpact();

    setState(() {
      _errorMessage = null;
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  Future<void> _handlePinCompleted() async {
    final pin = _enteredPin;

    if (_mode == PinMode.setup) {
      if (_firstEnteredPin == null) {
        // Step 1 of setup: save first entered PIN and prompt for confirmation
        setState(() {
          _firstEnteredPin = pin;
          _enteredPin = '';
        });
      } else {
        // Step 2 of setup: verify confirmation
        if (pin == _firstEnteredPin) {
          setState(() => _isLoading = true);
          await AppCacheService.instance.setPin(pin);
          if (!mounted) return;
          widget.onSuccess(context);
        } else {
          HapticFeedback.heavyImpact();
          setState(() {
            _errorMessage = 'PINs did not match. Try again.';
            _enteredPin = '';
            _firstEnteredPin = null;
          });
        }
      }
    } else if (_mode == PinMode.changePin) {
      // Verify current PIN before allowing change
      setState(() => _isLoading = true);
      final isValid = await AppCacheService.instance.verifyPin(pin);
      if (!mounted) return;

      if (isValid) {
        setState(() {
          _isLoading = false;
          _mode = PinMode.setup;
          _enteredPin = '';
          _firstEnteredPin = null;
          _errorMessage = null;
        });
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _isLoading = false;
          _errorMessage = 'Incorrect PIN';
          _enteredPin = '';
        });
      }
    } else {
      // PinMode.verify
      setState(() => _isLoading = true);
      final isValid = await AppCacheService.instance.verifyPin(pin);
      if (!mounted) return;

      if (isValid) {
        widget.onSuccess(context);
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _isLoading = false;
          _errorMessage = 'Incorrect PIN';
          _enteredPin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          color: const Color(0xFF141416).withValues(alpha: 0.95),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              const Icon(Icons.lock_outline, color: Colors.tealAccent, size: 28),
              const SizedBox(height: 12),

              Text(
                _title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 4 Dot indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _enteredPin.length;
                  final hasError = _errorMessage != null;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasError
                          ? Colors.redAccent
                          : (isFilled ? Colors.tealAccent : Colors.transparent),
                      border: Border.all(
                        color: hasError
                            ? Colors.redAccent
                            : (isFilled ? Colors.tealAccent : Colors.white38),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),

              // Error message
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                )
              else
                const SizedBox(height: 16),

              const SizedBox(height: 8),

              // Keypad
              _buildKeypad(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeypadButton('1'),
            _buildKeypadButton('2'),
            _buildKeypadButton('3'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeypadButton('4'),
            _buildKeypadButton('5'),
            _buildKeypadButton('6'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeypadButton('7'),
            _buildKeypadButton('8'),
            _buildKeypadButton('9'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 24),
              onPressed: () => Navigator.maybePop(context),
            ),
            _buildKeypadButton('0'),
            IconButton(
              icon: const Icon(Icons.backspace_outlined,
                  color: Colors.white70, size: 22),
              onPressed: _onBackspacePressed,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String digit) {
    return InkResponse(
      onTap: () => _onDigitPressed(int.parse(digit)),
      radius: 34,
      splashColor: Colors.tealAccent.withValues(alpha: 0.2),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white10),
        ),
        alignment: Alignment.center,
        child: Text(
          digit,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
