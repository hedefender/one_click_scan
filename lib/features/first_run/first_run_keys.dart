import 'package:flutter/widgets.dart';

/// Widget keys used by widget and integration tests.
abstract final class FirstRunKeys {
  static const next = Key('firstRun.next');
  static const back = Key('firstRun.back');
  static const pickFolder = Key('firstRun.pickFolder');
  static const sender = Key('firstRun.sender');
  static const customDestination = Key('firstRun.customDestination');
  static const gallerySwitch = Key('firstRun.gallerySwitch');
  static const flowOneClick = Key('firstRun.flow.oneClick');
  static const flowPreview = Key('firstRun.flow.preview');
  static const flowError = Key('firstRun.flow.error');
}
