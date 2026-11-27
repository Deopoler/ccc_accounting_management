import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Groups placeholder elements under a single screen-reader loading announcement.
class SkeletonRegion extends StatelessWidget {
  const SkeletonRegion({
    super.key,
    required this.child,
    this.label = '불러오는 중',
  });

  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: child,
    );
  }
}

/// Static rounded placeholder bar matching [AppColors.surfaceStrong].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
    this.announce = true,
  });

  final double? width;
  final double height;
  final double radius;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceStrong,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (!announce) return box;
    return Semantics(
      container: true,
      label: '불러오는 중',
      excludeSemantics: true,
      child: box,
    );
  }
}

/// Placeholder bar sized to a line of text to avoid vertical layout shift.
class SkeletonText extends StatelessWidget {
  const SkeletonText({
    super.key,
    this.width,
    this.maxWidth,
    this.fontSize = 14,
    this.lineHeight = 1.4,
    this.radius = 6,
    this.alignment = AlignmentDirectional.centerStart,
    this.announce = true,
  });

  final double? width;
  final double? maxWidth;
  final double fontSize;
  final double lineHeight;
  final double radius;
  final AlignmentGeometry alignment;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    Widget bar = SkeletonBox(
      width: width,
      height: fontSize,
      radius: radius,
      announce: false,
    );
    if (maxWidth != null) {
      bar = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: bar,
      );
    }
    final content = SizedBox(
      height: fontSize * lineHeight,
      child: Align(alignment: alignment, child: bar),
    );
    if (!announce) return content;
    return Semantics(
      container: true,
      label: '불러오는 중',
      excludeSemantics: true,
      child: content,
    );
  }
}

/// Placeholder list of cards or divider-separated tile rows.
class SkeletonList extends StatelessWidget {
  const SkeletonList.cards({
    super.key,
    this.count = 3,
    this.spacing = 12,
    required IndexedWidgetBuilder this.itemBuilder,
  }) : _isTiles = false,
       hasLeading = false,
       hasTrailing = false;

  const SkeletonList.tiles({
    super.key,
    this.count = 4,
    this.hasLeading = false,
    this.hasTrailing = false,
  }) : _isTiles = true,
       spacing = 0,
       itemBuilder = null;

  final int count;
  final double spacing;
  final IndexedWidgetBuilder? itemBuilder;
  final bool _isTiles;
  final bool hasLeading;
  final bool hasTrailing;

  @override
  Widget build(BuildContext context) {
    if (_isTiles) {
      return SkeletonRegion(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      if (hasLeading) ...[
                        const SkeletonBox(
                          width: 24,
                          height: 24,
                          radius: 6,
                          announce: false,
                        ),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonText(
                              maxWidth: i.isEven ? 140 : 180,
                              fontSize: 16,
                              announce: false,
                            ),
                            const SizedBox(height: 4),
                            SkeletonText(
                              maxWidth: i.isEven ? 210 : 170,
                              fontSize: 13,
                              announce: false,
                            ),
                          ],
                        ),
                      ),
                      if (hasTrailing) ...[
                        const SizedBox(width: 12),
                        const SkeletonBox(
                          width: 36,
                          height: 24,
                          radius: 8,
                          announce: false,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SkeletonRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            itemBuilder!(context, i),
          ],
        ],
      ),
    );
  }
}
