# App localization

Via Vera supports English (`en`) and Simplified Chinese (`zh-Hans`) on iOS,
iPadOS, and macOS. English is the development language and fallback.

The app uses the operating system’s preferred language order and per-app language
setting. It does not write `AppleLanguages`, persist its own language selection,
or override the SwiftUI locale. Reopen the app after changing its system language.

## String resources

- `OmniBot/Resources/Localizable.xcstrings` contains interface text and application
  error messages. Existing Chinese literals are retained as stable resource keys;
  both languages have explicit translated values, including English.
- `OmniBot/Resources/InfoPlist.xcstrings` contains localized permission descriptions
  and the bundle name. The base `Info.plist` descriptions use English.
- SwiftUI literal labels use native localization. Strings passed through models,
  variables, conditional expressions, or custom views use `String(localized:)`.
  Keep a whole sentence in one resource rather than concatenating fragments.
- Keep identifiers and persisted enum raw values independent of display titles.
  Do not translate user messages, provider/model IDs, file contents, tool packages,
  or authored agent instructions as interface labels.
- Use date format styles for dates and month labels instead of fixed Chinese suffixes.

## Verification without opening OmniBot

Run `python3 Scripts/test-localization.py` to check translation completeness,
format arguments, and privacy descriptions.

After building, pass `--app '/absolute/path/to/Via Vera.app'` to validate the actual
compiled resources and seven language/region combinations. The script compiles a
separate command-line probe with selected application models; it does not launch
OmniBot or render its interface. It supports both the macOS and iOS app bundles.

Pass `--stringsdata /path/to/OmniBot.build/Objects-normal/arm64` for each platform
to check that every Chinese key extracted by the Swift compiler has translations.
