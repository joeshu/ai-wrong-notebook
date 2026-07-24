import 'package:flutter/material.dart';

/// 统一的动效规范（Motion）。
///
/// 大厂级界面“不廉价”的关键之一是动效克制且一致：统一的时长档位、
/// 统一的缓动曲线、统一的方向。避免在各个页面硬编码 `Duration(milliseconds: 300)`。
abstract final class AppMotion {
  /// 极快：微小反馈（如开关、徽章变化）。
  static const Duration micro = Duration(milliseconds: 120);

  /// 快：列表项进入、卡片浮现。
  static const Duration fast = Duration(milliseconds: 240);

  /// 中：页面转场、较大容器变化。
  static const Duration medium = Duration(milliseconds: 360);

  /// 慢：Hero 级大元素。
  static const Duration slow = Duration(milliseconds: 520);

  /// 标准缓动（material 标准），先快后慢的减速曲线。
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// 强调缓动，入场更有“弹性感”。
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// 列表 stagger 的单步间隔。
  static const Duration staggerStep = Duration(milliseconds: 60);
}
