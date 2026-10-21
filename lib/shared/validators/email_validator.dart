final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Pragmatic e-mail check (shape only). Real validation happens when the
/// mail provider accepts the address in a later phase.
bool isValidEmail(String? value) {
  if (value == null) return false;
  return _emailPattern.hasMatch(value.trim());
}
