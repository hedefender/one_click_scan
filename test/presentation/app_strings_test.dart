import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/presentation/l10n/app_strings.dart';

void main() {
  test('delegate supports Greek and English only', () {
    expect(AppStrings.delegate.isSupported(const Locale('el')), isTrue);
    expect(AppStrings.delegate.isSupported(const Locale('en')), isTrue);
    expect(AppStrings.delegate.isSupported(const Locale('fr')), isFalse);
  });

  test('loads the right language', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(el.actionNext, 'Επόμενο');
    expect(en.actionNext, 'Next');
  });

  test('parameterised strings interpolate in both languages', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(en.wizardStepIndicator(2, 4), 'Step 2 of 4');
    expect(el.wizardStepIndicator(2, 4), 'Βήμα 2 από 4');
    expect(en.folderSelected('Scans'), contains('Scans'));
    expect(el.folderSelected('Scans'), contains('Scans'));
  });

  test('the Gallery note explains what sharing to the Gallery means', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(en.galleryNote, contains('Gallery'));
    expect(el.galleryNote, contains('Gallery'));
    expect(en.galleryNote.length, greaterThan(80));
    expect(el.galleryNote.length, greaterThan(80));
  });
}
