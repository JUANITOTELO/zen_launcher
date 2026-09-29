import 'package:flutter/material.dart';
import '../../core/services/wallpaper_service.dart';

class WallpaperTuningSheet extends StatefulWidget {
  final double currentPitch;

  const WallpaperTuningSheet({
    super.key,
    this.currentPitch = 6.0,
  });

  @override
  State<WallpaperTuningSheet> createState() => _WallpaperTuningSheetState();
}

class _WallpaperTuningSheetState extends State<WallpaperTuningSheet> {
  final WallpaperService _service = WallpaperService.instance;

  void _showMetadataDialog() {
    final meta = _service.metadata;
    final title = meta?['title'] ??
        (meta?['vector'] is Map ? meta!['vector']['raw_subject'] : null) ??
        'Daily Architectural Wallpaper';
    final desc = meta?['description'] ??
        meta?['prompt'] ??
        (meta?['vector'] is Map ? meta!['vector']['typology'] : null) ??
        'Procedurally synthesized 2.5D architectural wallpaper with depth disparity.';
    final atmosphere = meta?['vector'] is Map
        ? meta!['vector']['atmosphere'] as String?
        : null;
    final materials = meta?['vector'] is Map
        ? meta!['vector']['materials'] as String?
        : null;
    final timestamp = meta?['generated_at'] ??
        meta?['timestamp'] ??
        (meta?['vector'] is Map ? meta!['vector']['iso_date'] : null) ??
        'Daily Build';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16181A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                desc.toString(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
              if (atmosphere != null) ...[
                const SizedBox(height: 10),
                const Text(
                  'Atmosphere:',
                  style: TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  atmosphere,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              if (materials != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Materials:',
                  style: TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  materials,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Synthesized: $timestamp',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(
                color: Colors.tealAccent,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _recenterHoldingAngle() {
    _service.recenterHoldingAngle(widget.currentPitch);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Orientation recentered to current holding posture',
          style: TextStyle(fontFamily: 'monospace'),
        ),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final focusPlane = _service.focusPlane;
        final depthIntensity = _service.depthIntensity;
        final detailSensitivity = _service.detailSensitivity;
        final perspectiveWarp = _service.perspectiveWarp;
        final sheen = _service.sheen;
        final invertX = _service.invertX;
        final invertY = _service.invertY;
        final lockTouch = _service.lockTouchPosition;
        final isSyncing = _service.isSyncing;

        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141416).withValues(alpha: 0.97),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white10),
              ),
              child: ListView(
                controller: scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '2.5D Holographic Optics',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_service.metadata != null)
                            IconButton(
                              icon: const Icon(Icons.info_outline,
                                  color: Colors.tealAccent, size: 20),
                              tooltip: 'Wallpaper Telemetry',
                              onPressed: _showMetadataDialog,
                            ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white70, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Preset Mode Chips
                  const Text(
                    'Perspective Mode Preset',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text(
                            '🪟 Window',
                            style: TextStyle(
                                fontSize: 12, fontFamily: 'monospace'),
                          ),
                          selected: focusPlane >= 0.8,
                          selectedColor:
                              Colors.tealAccent.withValues(alpha: 0.25),
                          onSelected: (val) {
                            if (val) {
                              _service.applyPreset(
                                focusPlane: 0.88,
                                depthIntensity: 0.055,
                                overscan: 1.15,
                                detailSensitivity: 0.75,
                                perspectiveWarp: 0.38,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text(
                            '🎭 Diorama',
                            style: TextStyle(
                                fontSize: 12, fontFamily: 'monospace'),
                          ),
                          selected: focusPlane > 0.3 && focusPlane < 0.8,
                          selectedColor:
                              Colors.tealAccent.withValues(alpha: 0.25),
                          onSelected: (val) {
                            if (val) {
                              _service.applyPreset(
                                focusPlane: 0.50,
                                depthIntensity: 0.048,
                                overscan: 1.12,
                                detailSensitivity: 0.70,
                                perspectiveWarp: 0.32,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text(
                            '🔮 Pop-Out',
                            style: TextStyle(
                                fontSize: 12, fontFamily: 'monospace'),
                          ),
                          selected: focusPlane <= 0.3,
                          selectedColor:
                              Colors.tealAccent.withValues(alpha: 0.25),
                          onSelected: (val) {
                            if (val) {
                              _service.applyPreset(
                                focusPlane: 0.15,
                                depthIntensity: 0.052,
                                overscan: 1.14,
                                detailSensitivity: 0.80,
                                perspectiveWarp: 0.35,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Fine-Detail Protection Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Fine-Detail Protection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        '${(detailSensitivity * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: detailSensitivity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    activeColor: Colors.tealAccent,
                    onChanged: (val) => _service.setDetailSensitivity(val),
                  ),
                  const SizedBox(height: 8),

                  // 3D Perspective Keystone Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '3D Perspective Keystone',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        '${(perspectiveWarp * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: perspectiveWarp,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    activeColor: Colors.tealAccent,
                    onChanged: (val) => _service.setPerspectiveWarp(val),
                  ),
                  const SizedBox(height: 8),

                  // Depth Sensitivity Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Depth Disparity Intensity',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        '${(depthIntensity * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: depthIntensity,
                    min: 0.02,
                    max: 0.16,
                    divisions: 14,
                    activeColor: Colors.tealAccent,
                    onChanged: (val) => _service.setDepthIntensity(val),
                  ),
                  const SizedBox(height: 8),

                  // Focal Plane Depth Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Focal Plane Depth',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        focusPlane >= 0.8
                            ? 'Window Glass'
                            : (focusPlane <= 0.2
                                ? 'Deep Background'
                                : 'Center Pivot'),
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: focusPlane,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    activeColor: Colors.tealAccent,
                    onChanged: (val) => _service.setFocusPlane(val),
                  ),
                  const SizedBox(height: 8),

                  // Holographic Sheen & Relief Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Holographic Sheen & Relief',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        (sheen * 1000).toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: sheen,
                    min: 0.0,
                    max: 0.04,
                    divisions: 10,
                    activeColor: Colors.tealAccent,
                    onChanged: (val) => _service.setSheen(val),
                  ),
                  const SizedBox(height: 8),

                  // Invert Axes Switches
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Invert X',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          value: invertX,
                          activeThumbColor: Colors.tealAccent,
                          onChanged: (val) => _service.setInvertX(val),
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Invert Y',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          value: invertY,
                          activeThumbColor: Colors.tealAccent,
                          onChanged: (val) => _service.setInvertY(val),
                        ),
                      ),
                    ],
                  ),

                  // Touch Persistence Switch
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Touch Persistence',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    subtitle: Text(
                      lockTouch
                          ? 'Position stays where dragged'
                          : 'Spring back to gyroscope on release',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    value: lockTouch,
                    activeThumbColor: Colors.tealAccent,
                    onChanged: (val) => _service.setLockTouchPosition(val),
                  ),
                  const SizedBox(height: 16),

                  // Action Buttons: Recenter and Refresh
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.tealAccent,
                            side: const BorderSide(color: Colors.tealAccent),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            _recenterHoldingAngle();
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.screen_rotation, size: 16),
                          label: const Text(
                            'Recenter Posture',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: isSyncing
                              ? null
                              : () async {
                                  await _service.syncWallpaper();
                                },
                          icon: isSyncing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh, size: 16),
                          label: Text(
                            isSyncing ? 'Syncing...' : 'Sync Wallpaper',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
