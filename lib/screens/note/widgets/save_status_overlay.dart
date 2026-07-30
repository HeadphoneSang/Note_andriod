import 'package:flutter/material.dart';

/// 右下角保存动画 + 底部"最近保存时间"文字
class SaveStatusOverlay extends StatelessWidget {
  final ValueNotifier<bool> isFlushingNotifier;
  final ValueNotifier<DateTime?> lastSavedTime;

  const SaveStatusOverlay({
    super.key,
    required this.isFlushingNotifier,
    required this.lastSavedTime,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: isFlushingNotifier,
          builder: (context, isFlushing, _) {
            return AnimatedOpacity(
              opacity: isFlushing ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.only(right: 16, bottom: 16),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ValueListenableBuilder<DateTime?>(
              valueListenable: lastSavedTime,
              builder: (context, time, _) {
                if (time == null) return const SizedBox.shrink();
                final formatted =
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                return Text(
                  '最近一次保存: $formatted',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
