# Phase 0: manual validation (performed by the user)

Use your own emulator or phone. Claude Code never touches your emulator.

## Before you start

```
flutter pub get
flutter analyze
flutter test
flutter run
```

## Checklist

1. **Launch.** The app opens on the wizard, "Step 1 of 4".
2. **Language.** Tap `Ελληνικά`: the whole screen switches to Greek at once.
   Tap `English`: back to English.
3. **Folder (real picker).**
   - Tap Next without choosing a folder: an error asks you to choose one, and you stay on step 2.
   - Tap "Choose folder": the Android system folder picker opens. Choose or create a folder and confirm.
   - The folder name appears under the button.
4. **Folder permission persists.** Finish the wizard, fully close the app,
   reopen it: it goes to home (no wizard). The folder name is shown on home.
5. **Mail step validation.**
   - Next with nothing filled in: errors for provider and email.
   - Type an invalid address: error. Type a valid one (any `name@example.com`): error disappears.
   - Switch to "To another email": a second field appears and must also be valid.
6. **Gallery step.** The explanation text is shown and the switch is **off** by default.
7. **Finish.** You land on home. SCAN & SEND shows the "camera arrives in the next phase" message.
8. **Interrupted wizard.** Reinstall or clear app data. Go to step 3, answer
   step 2, kill the app, reopen: the wizard restarts at step 1 with your
   language and folder prefilled.
9. **Dark mode.** Switch the device to dark mode: screens stay readable.
10. **Rotation** (optional): the wizard keeps its answers.

## Report back

Tell me what passed, what failed, and screenshots of anything odd. After you
commit, I will move to Phase 1 (camera) only when you confirm.
