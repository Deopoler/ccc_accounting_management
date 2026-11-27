import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/error_message.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(semanticsLabel: '불러오는 중'),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.message = '표시할 항목이 없습니다.',
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              errorMessage(error),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Helpers for distinguishing safe in-place refreshes from scope-change reloads.
extension AsyncValueDisplay<T> on AsyncValue<T> {
  /// True when data is safe to render without flashing another user's or
  /// campus's previous state during a dependency reload or after an error.
  bool get hasUsableValue => hasValue && !hasError && !isReloading;

  /// True when refreshing already-visible data in the background.
  bool get isBackgroundRefreshing => isRefreshing && hasValue && !hasError;
}

/// Overlays a thin progress bar at the top edge without shifting [child].
class RefreshOverlay extends StatelessWidget {
  const RefreshOverlay({
    super.key,
    required this.refreshing,
    required this.child,
  });

  final bool refreshing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (refreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ExcludeSemantics(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ),
      ],
    );
  }
}

/// [AsyncValue] 의 로딩 / 에러 / 빈 상태 / 데이터를 한 번에 처리한다.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.isEmpty,
    this.empty,
    this.skipLoadingOnReload = false,
    this.showRefreshIndicator = true,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final bool skipLoadingOnReload;
  final bool showRefreshIndicator;

  @override
  Widget build(BuildContext context) {
    final keepingData =
        value.hasValue &&
        !value.hasError &&
        (value.isRefreshing || (skipLoadingOnReload && value.isReloading));
    final Widget content;
    if (value.isLoading && !keepingData) {
      content = const LoadingView();
    } else if (value.hasError && !keepingData) {
      content = ErrorView(error: value.error!, onRetry: onRetry);
    } else if (value.hasValue) {
      final d = value.requireValue;
      content = (isEmpty?.call(d) ?? false)
          ? (empty ?? const EmptyView())
          : data(d);
    } else {
      content = const LoadingView();
    }
    if (!showRefreshIndicator) return content;
    return RefreshOverlay(
      refreshing: value.isLoading && keepingData,
      child: content,
    );
  }
}
