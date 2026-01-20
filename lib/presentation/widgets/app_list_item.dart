import 'package:flutter/material.dart';
import '../../../domain/models/zen_app.dart';
import '../../../core/services/app_cache_service.dart';

class AppListItem extends StatelessWidget {
  final ZenApp zenApp;
  final bool isHighlighted;

  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  const AppListItem({
    super.key,
    required this.zenApp,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AppCacheService.instance.launchApp(zenApp),
      splashColor: Colors.white10,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 25,
          vertical: zenApp.isNew ? 5 : 0,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      zenApp.info.name,
                      style: TextStyle(
                        fontSize: 16,
                        color: isHighlighted
                            ? Colors.amberAccent
                            : Colors.white,
                        fontWeight: isHighlighted
                            ? FontWeight.bold
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                  if (zenApp.isNew)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "NEW",
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            SizedBox(
              width: 28,
              height: 28,
              child: zenApp.info.icon != null
                  ? ColorFiltered(
                      colorFilter: _grayscaleFilter,
                      child: Image.memory(
                        zenApp.info.icon!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    )
                  : const Icon(Icons.android, size: 28, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
