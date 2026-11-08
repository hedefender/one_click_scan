import 'package:flutter/widgets.dart';

/// Widget keys used by widget and integration tests.
abstract final class ScanKeys {
  static const modeSelector = Key('scan.mode');
  static const stopContinue = Key('scan.stop.continue');
  static const stopConfirm = Key('scan.stop.confirm');
  static const saveCancel = Key('scan.save.cancel');
  static const saveCancelled = Key('scan.save.cancelled');
  static const autoReturn = Key('scan.result.autoReturn');
  static const preview = Key('scan.preview');
  static const capture = Key('scan.capture');
  static const done = Key('scan.done');
  static const deleteLast = Key('scan.deleteLast');
  static const thumbnails = Key('scan.thumbnails');
  static const saving = Key('scan.saving');
  static const retryCamera = Key('scan.retryCamera');
  static const openAppSettings = Key('scan.openAppSettings');
  static const retrySave = Key('scan.retrySave');
  static const folderOpenSettings = Key('scan.folderOpenSettings');
  static const captureFailed = Key('scan.captureFailed');
  static const dialogDiscard = Key('scan.dialog.discard');
  static const dialogStay = Key('scan.dialog.stay');
  static const resultList = Key('scan.result.list');
  static const resultBack = Key('scan.result.back');
  static const resultOcr = Key('scan.result.ocr');
  static const resultSummary = Key('scan.result.summary');
  static const pdfPages = Key('scan.result.pdfPages');
  static Key pdfPage(int index) => Key('scan.result.pdfPage.$index');
  static const flowStatus = Key('scan.result.flow.status');
  static const flowCancel = Key('scan.result.flow.cancel');
  static const flowCancelled = Key('scan.result.flow.cancelled');
  static const flowNotSent = Key('scan.result.flow.notSent');
  static const discard = Key('scan.result.discard');
  static const discardConfirm = Key('scan.result.discard.confirm');
  static const discardKeep = Key('scan.result.discard.keep');
  static const discardStatus = Key('scan.result.discard.status');
  static const pdfStatus = Key('scan.result.pdf.status');
  static const pdfDetails = Key('scan.result.pdf.details');
  static const pdfNoText = Key('scan.result.pdf.noText');
  static const pdfNote = Key('scan.result.pdf.note');
  static const pdfOpen = Key('scan.result.pdf.open');
  static const pdfOpenProblem = Key('scan.result.pdf.openProblem');
  static const pdfSkipText = Key('scan.result.pdf.skipText');
  static const pdfRetry = Key('scan.result.pdf.retry');
  static const pdfFailure = Key('scan.result.pdf.failure');

  static const mailStatus = Key('scan.result.mail.status');
  static const mailNote = Key('scan.result.mail.note');
  static const mailSend = Key('scan.result.mail.send');
  static const mailCancel = Key('scan.result.mail.cancel');
  static const mailRetry = Key('scan.result.mail.retry');
  static const mailFallback = Key('scan.mail.fallback');
  static const mailFallbackReason = Key('scan.mail.fallbackReason');
  static const mailGuide = Key('scan.mail.guide');
  static const mailDiagnostic = Key('scan.mail.diagnostic');
  static const mailOpenApp = Key('scan.result.mail.openApp');
  static const mailOpenSettings = Key('scan.result.mail.openSettings');
  static const mailFailure = Key('scan.result.mail.failure');
  static const mailDraft = Key('scan.result.mail.draft');

  // Phase 6.2
  static const flashButton = Key('scan.flash');
  static const lowLightChip = Key('scan.lowLight.chip');
  static const focusRing = Key('scan.focus.ring');
  static const torchIdleOff = Key('scan.torch.idleOff');
  static const lowLightBannerRetake = Key('scan.result.lowLight.retake');
  static const lowLightDialog = Key('scan.lowLight.dialog');
  static const lowLightRetake = Key('scan.lowLight.retake');
  static const lowLightContinue = Key('scan.lowLight.continue');
  static const lowLightEnhance = Key('scan.lowLight.enhance');
  static const darkBar = Key('scan.lowLight.bar');
  static const darkBarRetake = Key('scan.lowLight.bar.retake');
  static const darkBarDismiss = Key('scan.lowLight.bar.dismiss');
  static const lowLightBanner = Key('scan.result.lowLight.banner');
  static const lowLightImprove = Key('scan.result.lowLight.improve');
  static const lowLightKeep = Key('scan.result.lowLight.keep');
  static const lowLightStatus = Key('scan.result.lowLight.status');
  static const lightDiagLive = Key('scan.lightDiag.live');
  static const lightDiagShot = Key('scan.lightDiag.shot');
  static const lightDiagTake = Key('scan.lightDiag.take');

  // Phase 6.3
  static const pageCounter = Key('scan.pageCounter');
  static const pageBudgetNote = Key('scan.pageBudget.note');
  static const pageLimitReached = Key('scan.pageBudget.reached');
  static const captureBusy = Key('scan.capture.busy');
  static const multiHint = Key('scan.multiHint');
  static const multiHintOk = Key('scan.multiHint.ok');

  static Key resultFile(String fileName) => Key('scan.result.file.$fileName');
}
