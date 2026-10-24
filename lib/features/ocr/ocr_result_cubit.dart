import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/usecases/recognize_pages.dart';

class OcrResultState extends Equatable {
  const OcrResultState({required this.snapshot, this.pageIndex = 0});

  final OcrSessionSnapshot snapshot;
  final int pageIndex;

  int get pageCount => snapshot.pages.length;

  /// The page being shown, or null when there is none yet.
  OcrPageState? get page =>
      pageIndex < pageCount ? snapshot.pages[pageIndex] : null;

  bool get hasPrevious => pageIndex > 0;
  bool get hasNext => pageIndex < pageCount - 1;

  OcrResultState copyWith({OcrSessionSnapshot? snapshot, int? pageIndex}) {
    return OcrResultState(
      snapshot: snapshot ?? this.snapshot,
      pageIndex: pageIndex ?? this.pageIndex,
    );
  }

  @override
  List<Object?> get props => [snapshot, pageIndex];
}

/// Mirrors the OCR session of the scan: progress while it reads, the lines
/// when it is done, and which page the check screen shows.
class OcrResultCubit extends Cubit<OcrResultState> {
  OcrResultCubit(OcrSession session)
    : super(OcrResultState(snapshot: session.snapshot)) {
    _subscription = session.snapshots.listen((snapshot) {
      final last = snapshot.pages.isEmpty ? 0 : snapshot.pages.length - 1;
      emit(
        state.copyWith(
          snapshot: snapshot,
          pageIndex: state.pageIndex > last ? last : state.pageIndex,
        ),
      );
    });
  }

  late final StreamSubscription<OcrSessionSnapshot> _subscription;

  void showPage(int index) {
    if (index < 0 || index >= state.pageCount) return;
    emit(state.copyWith(pageIndex: index));
  }

  void next() => showPage(state.pageIndex + 1);

  void previous() => showPage(state.pageIndex - 1);

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
