import 'package:flutter/cupertino.dart';
import 'package:meta/meta.dart';

import '../../pull_down_button.dart';
import 'animation.dart';
import 'menu.dart';
import 'route.dart';

/// Pull-down menu displayed by [PullDownButton] or [showPullDownMenu].
@immutable
@internal
class RoutePullDownMenu extends StatelessWidget {
  /// Creates [RoutePullDownMenu].
  const RoutePullDownMenu({
    super.key,
    required this.items,
    required this.routeTheme,
    required this.alignment,
    required this.animation,
    required this.topWidget,
  });

  final Widget? topWidget;

  /// Items to show in the menu.
  final List<PullDownMenuEntry> items;

  /// A per menu custom theme.
  ///
  /// Final theme is resolved using [PullDownMenuRouteTheme.resolve].
  final PullDownMenuRouteTheme? routeTheme;

  /// An animation provided by [PullDownMenuRoute] for scale, fade and size
  /// transitions.
  final Animation<double> animation;

  /// The point menu scales from.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme =
        PullDownMenuRouteTheme.resolve(context, routeTheme: routeTheme);
    final shadowTween = DecorationTween(
      begin: BoxDecoration(boxShadow: [theme.beginShadow!]),
      end: BoxDecoration(boxShadow: [theme.endShadow!]),
    );

    // Since [kCurve] has an overshoot at the end and only [ScaleTransition]
    // requires it, [_ClampedAnimation] is introduced for every other
    // *Transition* widget.
    final clampedAnimation = ClampedAnimation(animation);

    final shadow = CurveTween(curve: const Interval(1 / 3, 1));

    return ScaleTransition(
      scale: animation,
      alignment: alignment,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (topWidget != null)
            FadeTransition(
              opacity: clampedAnimation,
              child: topWidget!,
            ),
          DecoratedBoxTransition(
            decoration: shadow.animate(clampedAnimation).drive(shadowTween),
            child: FadeTransition(
              opacity: clampedAnimation,
              child: MenuDecoration(
                backgroundColor: theme.backgroundColor!,
                borderRadius: theme.borderRadius!,
                child: FadeTransition(
                  opacity: clampedAnimation,
                  child: ConstrainedBox(
                    constraints: BoxConstraints.tightFor(
                      width: theme.width,
                    ),
                    child: SizeTransition(
                      axisAlignment: -1,
                      sizeFactor: clampedAnimation,
                      child: MenuBody(
                        items: items,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
