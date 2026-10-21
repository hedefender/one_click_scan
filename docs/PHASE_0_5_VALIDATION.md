# Phase 0.5: manual validation (performed by the user)

Use your own emulator or phone. Claude Code never touches your emulator.

```
flutter pub get
flutter analyze
flutter test
flutter run
```

1. **Open settings.** On home, tap the gear icon in the app bar: the Settings screen opens.
2. **Language.** Tap `Ελληνικά`: the screen switches to Greek at once. Go back to home: it is Greek too. Switch back to English.
3. **E-mail change.**
   - Type an invalid address in the sending account: an error appears and `Save` stays disabled.
   - Type a valid one (`name@example.com`): the error goes away and `Save` becomes active. Tap it: "Settings saved." appears.
   - Fully close the app and reopen it: home and settings show the new value.
4. **Unsaved changes.** Change the address (do not save) and press back: a dialog appears. `Stay` keeps you editing. `Discard` leaves and the old value is kept.
5. **Change folder (real picker).** Tap "Change folder", choose another folder in the system picker. Settings shows the new name; go back to home: it shows the new folder.
6. **Lost access.** Revoke the app's access to the folder (Android: system settings, or delete or move the folder), then return to the app: home shows "The folder is no longer accessible" with a Settings button. Settings shows the warning under the folder. Choosing a folder again clears both.
7. **Gallery switch.** Toggle it: it changes at once. Fully close and reopen the app: it keeps its value.
8. **Dark mode.** Switch the device to dark mode: home, settings, the dialog and the banner are all readable.
