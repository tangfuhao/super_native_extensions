import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

import 'util.dart';

class MenuLayoutInput {
  MenuLayoutInput({
    required this.layoutMenu,
    required this.bounds,
    required this.primaryItem,
    required this.menuPreviewSize,
    required this.menuDragOffset,
    required this.previousLayoutId,
  });

  final Size Function(BoxConstraints) layoutMenu;
  final Rect bounds;
  final Rect primaryItem;
  final Size menuPreviewSize;
  final double menuDragOffset;
  final String? previousLayoutId;
}

class MenuLayout {
  MenuLayout({
    required this.previewRect,
    required this.menuPosition,
    required this.menuDragExtent,
    required this.canScrollMenu,
    required this.menuAlignment,
    required this.layoutId,
  });

  final String layoutId;
  final Rect previewRect;
  final MenuPosition menuPosition;
  final double menuDragExtent;
  final bool canScrollMenu;
  final AlignmentGeometry menuAlignment;
}

typedef MenuPosition = Offset Function(Rect previewRect);

const _epsilon = 0.001;

class _MenuGeometry {
  final String id;
  final Rect previewRect;
  final Size menuSize;
  final MenuPosition menuPosition;
  final AlignmentGeometry menuAlignment;

  _MenuGeometry({
    required this.id,
    required this.previewRect,
    required this.menuSize,
    required this.menuPosition,
    required this.menuAlignment,
  });

  Rect get menuRect {
    final position = menuPosition(previewRect);
    return Rect.fromLTWH(
      position.dx,
      position.dy,
      menuSize.width,
      menuSize.height,
    );
  }

  Rect get bounds => previewRect.expandToInclude(menuRect);

  bool fitsInto(Rect rect) {
    final bounds = this.bounds;
    return bounds.left + _epsilon >= rect.left &&
        bounds.right <= rect.right + _epsilon &&
        bounds.top + _epsilon >= rect.top &&
        bounds.bottom <= rect.bottom + _epsilon;
  }

  /// Try to keep the menu preview in the same position vertically as before.
  _MenuGeometry _fitIntoHorizontal(Rect rect) {
    final res = _fitInto(rect);
    final desiredPreviewRect = previewRect.moveIntoRect(rect);
    final correction = Offset(
      0,
      res.previewRect.center.dy - desiredPreviewRect.center.dy,
    );

    return _MenuGeometry(
      id: res.id,
      menuAlignment: res.menuAlignment,
      menuPosition: (pos) => res.menuPosition(pos) + correction,
      menuSize: res.menuSize,
      previewRect: res.previewRect.shift(-correction),
    );
  }

  _MenuGeometry fitInto(Rect rect) {
    if (menuRect.left > previewRect.right ||
        menuRect.right < previewRect.left) {
      return _fitIntoHorizontal(rect);
    } else {
      return _fitInto(rect);
    }
  }

  _MenuGeometry _fitInto(Rect rect) {
    final bounds = this.bounds;
    final dx1 = bounds.left < rect.left ? rect.left - bounds.left : 0.0;
    final dx2 = bounds.right > rect.right ? rect.right - bounds.right : 0.0;
    final dy1 = bounds.top < rect.top ? rect.top - bounds.top : 0.0;
    final dy2 = bounds.bottom > rect.bottom ? rect.bottom - bounds.bottom : 0.0;
    final offset = Offset(dx1 + dx2, dy1 + dy2);
    return _MenuGeometry(
      id: id,
      previewRect: previewRect.shift(offset),
      menuSize: menuSize,
      menuPosition: menuPosition,
      menuAlignment: menuAlignment,
    );
  }
}

/// Picks the geometry that fits best inside the bounds and shifts just enough
/// to fit in the bounds.
_MenuGeometry _bestFitGeometry(
  Rect bounds,
  List<_MenuGeometry> geometry,
  String? previousLayoutId,
) {
  if (previousLayoutId != null) {
    final previous = geometry.firstWhereOrNull(
      (element) => element.id == previousLayoutId,
    );
    if (previous != null) {
      return previous.fitInto(bounds);
    }
  }
  // Try to find first element that fully fits
  final firstThatFits = geometry.firstWhereOrNull(
    (element) => element.fitsInto(bounds),
  );
  if (firstThatFits != null) {
    return firstThatFits;
  }

  final geometryThatFits = geometry
      .where((element) => element.bounds.size <= bounds.size.inflate(_epsilon))
      .toList(growable: false);

  if (geometryThatFits.isEmpty) {
    return geometry.first;
  }

  // Find which ever geometry needs least adjustment relative to preview rect
  // to fit into bounds
  final best = geometryThatFits.reduce((value, element) {
    final v1 = value.fitInto(bounds);
    final v2 = element.fitInto(bounds);
    final d1 =
        (v1.previewRect.center - value.previewRect.center).distanceSquared;
    final d2 =
        (v2.previewRect.center - element.previewRect.center).distanceSquared;
    return d1 <= d2 + _epsilon ? value : element;
  });
  return best.fitInto(bounds);
}

abstract class MenuLayoutStrategy {
  MenuLayout layout(MenuLayoutInput input);

  static MenuLayoutStrategy forSize(Size screenSize) {
    if (screenSize.shortestSide < 550) {
      // phone layout
      if (screenSize.height > screenSize.width) {
        return _MenuLayoutMobilePortrait();
      } else {
        return _MenuLayout(allowVerticalAttachment: false);
      }
    } else {
      return _MenuLayout(allowVerticalAttachment: true);
    }
  }
}

const _kMenuSpacing = 15.0;

class _MenuLayout extends MenuLayoutStrategy {
  _MenuLayout({required this.allowVerticalAttachment});

  final bool allowVerticalAttachment;

  @override
  MenuLayout layout(MenuLayoutInput input) {
    final menuSize = input.layoutMenu(BoxConstraints.loose(input.bounds.size));
    final spaceForPreview = Size(
      input.bounds.width - menuSize.width - _kMenuSpacing,
      input.bounds.height,
    );
    final previewSize = input.menuPreviewSize.fitInto(spaceForPreview);
    final previewRect = Rect.fromCenter(
      center: input.primaryItem.center,
      width: previewSize.width,
      height: previewSize.height,
    );

    final vertical = [
      // Aligned to bottom left corner
      _MenuGeometry(
        id: 'vertical-bottom-left',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (previewRect) =>
            Offset(previewRect.left, previewRect.bottom + _kMenuSpacing),
        menuAlignment: Alignment.topLeft,
      ),
      // Aligned to bottom right corner
      _MenuGeometry(
        id: 'vertical-bottom-right',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (previewRect) => Offset(
          previewRect.right - menuSize.width,
          previewRect.bottom + _kMenuSpacing,
        ),
        menuAlignment: Alignment.topRight,
      ),
      // Aligned to top left corner
      _MenuGeometry(
        id: 'vertical-top-left',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (previewRect) => Offset(
          previewRect.left,
          previewRect.top - _kMenuSpacing - menuSize.height,
        ),
        menuAlignment: Alignment.bottomLeft,
      ),
      // Aligned to top right corner
      _MenuGeometry(
        id: 'vertical-top-right',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (previewRect) => Offset(
          previewRect.right - menuSize.width,
          previewRect.top - _kMenuSpacing - menuSize.height,
        ),
        menuAlignment: Alignment.bottomRight,
      ),
    ];

    final horizontal = [
      // Aligned to top right corner
      _MenuGeometry(
        id: 'horizontal-top-right',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (previewRect) =>
            Offset(previewRect.right + _kMenuSpacing, previewRect.top),
        menuAlignment: Alignment.topLeft,
      ),
      // Aligned to bottom right corner
      _MenuGeometry(
        id: 'horizontal-bottom-right',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (previewRect) => Offset(
          previewRect.right + _kMenuSpacing,
          previewRect.bottom - menuSize.height,
        ),
        menuAlignment: Alignment.bottomLeft,
      ),
      // Aligned to top left corner
      _MenuGeometry(
        id: 'horizontal-top-left',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (previewRect) => Offset(
          previewRect.left - _kMenuSpacing - menuSize.width,
          previewRect.top,
        ),
        menuAlignment: Alignment.topRight,
      ),
      // Aligned to bottom left corner
      _MenuGeometry(
        id: 'horizontal-bottom-left',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (previewRect) => Offset(
          previewRect.left - _kMenuSpacing - menuSize.width,
          previewRect.bottom - menuSize.height,
        ),
        menuAlignment: Alignment.bottomRight,
      ),
    ];

    final List<_MenuGeometry> geometries;
    if (allowVerticalAttachment &&
        input.menuPreviewSize.width > input.menuPreviewSize.height) {
      // prefer vertical attachment on wide previews
      geometries = [...vertical, ...horizontal];
    } else if (allowVerticalAttachment) {
      // prefer horizontal attachment on wide previews
      geometries = [...horizontal, ...vertical];
    } else {
      geometries = horizontal;
    }

    final geometry = _bestFitGeometry(
      input.bounds,
      geometries,
      input.previousLayoutId,
    );

    return MenuLayout(
      layoutId: geometry.id,
      previewRect: geometry.previewRect,
      menuPosition: geometry.menuPosition,
      menuDragExtent: 0.0,
      canScrollMenu: true,
      menuAlignment: geometry.menuAlignment,
    );
  }
}

class _MenuLayoutMobilePortrait extends MenuLayoutStrategy {
  // 水平边距
  static const _kHorizontalPadding = 12.0;

  @override
  MenuLayout layout(MenuLayoutInput input) {
    // 计算预览尺寸限制
    final menuPreviewSizeMin = input.menuPreviewSize.fitInto(
      Size(input.bounds.width, input.bounds.height / 4),
    );
    final menuPreviewSizeMax = input.menuPreviewSize.fitInto(
      Size(input.bounds.width, input.bounds.height * 3 / 4),
    );

    // 计算菜单尺寸
    final menuSize = input.layoutMenu(
      BoxConstraints.loose(
        Size(
          input.bounds.width - _kHorizontalPadding * 2,
          input.bounds.height - menuPreviewSizeMin.height - _kMenuSpacing,
        ),
      ),
    );

    // final menuOverflow = math.max(
    //   menuPreviewSizeMax.height +
    //       _kMenuSpacing +
    //       menuSize.height -
    //       input.bounds.height,
    //   0.0,
    // );
    final menuOverflow = 0.0; // 禁用拖拽调整

    final menuDragOffset = input.menuDragOffset * menuOverflow;

    final actualMenuPreviewSize = input.menuPreviewSize.fitInto(
      Size(input.bounds.width, menuPreviewSizeMax.height - menuDragOffset),
    );

    // 策略1: 预览位置尽量不变 - 直接使用原始 item 的中心位置
    final previewRect = Rect.fromCenter(
      center: input.primaryItem.center,
      width: actualMenuPreviewSize.width,
      height: actualMenuPreviewSize.height,
    );

    // 将预览限制在水平边界内（只做水平调整，不做垂直调整）
    final clampedPreviewRect = _clampHorizontally(previewRect, input.bounds);

    // 策略2: 计算上下空间，决定菜单方向
    final spaceAbove = clampedPreviewRect.top - input.bounds.top;
    final spaceBelow = input.bounds.bottom - clampedPreviewRect.bottom;
    final menuNeedsHeight = menuSize.height + _kMenuSpacing;

    // 优先向下布局，空间不够时向上
    final preferBottom =
        spaceBelow >= menuNeedsHeight ||
        spaceBelow >= spaceAbove ||
        spaceAbove < menuNeedsHeight;

    // 策略3: 水平对齐 - 左对齐 → 右对齐 → 居中
    final geometries = _buildGeometries(
      previewRect: clampedPreviewRect,
      menuSize: menuSize,
      bounds: input.bounds,
      preferBottom: preferBottom,
    );

    // 调整边界以容纳溢出
    final adjustedBounds = input.bounds.copyWith(
      height: input.bounds.height + menuOverflow,
    );

    final geometry = _bestFitGeometry(
      adjustedBounds,
      geometries,
      input.previousLayoutId,
    );

    return MenuLayout(
      layoutId: geometry.id,
      previewRect: geometry.previewRect,
      menuDragExtent: menuOverflow,
      canScrollMenu: menuOverflow == 0.0 || input.menuDragOffset == 1.0,
      menuPosition: geometry.menuPosition,
      menuAlignment: geometry.menuAlignment,
    );
  }

  /// 只在水平方向上限制预览位置，保持垂直位置不变
  Rect _clampHorizontally(Rect rect, Rect bounds) {
    var left = rect.left;
    if (left < bounds.left + _kHorizontalPadding) {
      left = bounds.left + _kHorizontalPadding;
    } else if (rect.right > bounds.right - _kHorizontalPadding) {
      left = bounds.right - _kHorizontalPadding - rect.width;
    }
    return Rect.fromLTWH(left, rect.top, rect.width, rect.height);
  }

  /// 构建所有可能的几何布局
  List<_MenuGeometry> _buildGeometries({
    required Rect previewRect,
    required Size menuSize,
    required Rect bounds,
    required bool preferBottom,
  }) {
    final List<_MenuGeometry> bottomGeometries = [];
    final List<_MenuGeometry> topGeometries = [];

    // 计算菜单的水平位置选项
    final menuLeftAligned = previewRect.left;
    final menuRightAligned = previewRect.right - menuSize.width;

    // 检查左对齐是否可行（不超出边界）
    final leftAlignedFits =
        menuLeftAligned >= bounds.left + _kHorizontalPadding &&
        menuLeftAligned + menuSize.width <= bounds.right - _kHorizontalPadding;

    // 检查右对齐是否可行
    final rightAlignedFits =
        menuRightAligned >= bounds.left + _kHorizontalPadding &&
        menuRightAligned + menuSize.width <= bounds.right - _kHorizontalPadding;

    // === 下方布局 ===
    if (leftAlignedFits) {
      bottomGeometries.add(
        _MenuGeometry(
          id: 'bottom-left',
          previewRect: previewRect,
          menuSize: menuSize,
          menuPosition: (p) => Offset(p.left, p.bottom + _kMenuSpacing),
          menuAlignment: Alignment.topLeft,
        ),
      );
    }
    if (rightAlignedFits) {
      bottomGeometries.add(
        _MenuGeometry(
          id: 'bottom-right',
          previewRect: previewRect,
          menuSize: menuSize,
          menuPosition: (p) =>
              Offset(p.right - menuSize.width, p.bottom + _kMenuSpacing),
          menuAlignment: Alignment.topRight,
        ),
      );
    }
    // 居中作为备选
    bottomGeometries.add(
      _MenuGeometry(
        id: 'bottom-center',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (p) => Offset(
          (bounds.left + bounds.right) / 2 - menuSize.width / 2,
          p.bottom + _kMenuSpacing,
        ),
        menuAlignment: Alignment.topCenter,
      ),
    );

    // === 上方布局 ===
    if (leftAlignedFits) {
      topGeometries.add(
        _MenuGeometry(
          id: 'top-left',
          previewRect: previewRect,
          menuSize: menuSize,
          menuPosition: (p) =>
              Offset(p.left, p.top - _kMenuSpacing - menuSize.height),
          menuAlignment: Alignment.bottomLeft,
        ),
      );
    }
    if (rightAlignedFits) {
      topGeometries.add(
        _MenuGeometry(
          id: 'top-right',
          previewRect: previewRect,
          menuSize: menuSize,
          menuPosition: (p) => Offset(
            p.right - menuSize.width,
            p.top - _kMenuSpacing - menuSize.height,
          ),
          menuAlignment: Alignment.bottomRight,
        ),
      );
    }
    // 居中作为备选
    topGeometries.add(
      _MenuGeometry(
        id: 'top-center',
        previewRect: previewRect,
        menuSize: menuSize,
        menuPosition: (p) => Offset(
          (bounds.left + bounds.right) / 2 - menuSize.width / 2,
          p.top - _kMenuSpacing - menuSize.height,
        ),
        menuAlignment: Alignment.bottomCenter,
      ),
    );

    // 根据偏好方向返回几何布局列表
    if (preferBottom) {
      return [...bottomGeometries, ...topGeometries];
    } else {
      return [...topGeometries, ...bottomGeometries];
    }
  }
}
