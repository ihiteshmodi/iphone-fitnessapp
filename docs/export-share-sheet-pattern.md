# Export pattern: straight to the iOS share sheet

How this app exports its database, so other apps can do the same. Hand this file to the agent working on the other app.

## The behaviour we want

1. The user taps **Export database**.
2. The **iOS share sheet opens at once**: AirDrop, Messages, Mail, **Save to Files**, **Google Drive**, other apps.
3. One more tap sends the file wherever it should go.

## What to avoid

Do **not** open the Files picker first ("Save to…"). That is the two-step flow: save into Files, find the file, tap Share,
and only then get the share sheet. In code that flow comes from:

- SwiftUI `.fileExporter(isPresented:document:contentType:...)`
- UIKit `UIDocumentPickerViewController(forExporting:)`

Remove these from the export button. **Save to Files** is still one of the choices in the share sheet, so nothing is lost.

## How it works (three pieces)

### 1. Write the file to a temporary folder and return its URL

Write a finished file into a fresh folder under `FileManager.default.temporaryDirectory`, name it with the date, and
return the `URL`. The share sheet shares this file. The temporary folder needs no cleanup because iOS clears it.

```swift
/// Called by the Export button. Returns the file to share.
func exportDatabase() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let target = directory.appendingPathComponent("myapp-\(todayISO()).sqlite")   // e.g. myapp-2026-11-19.sqlite
    // SQLite: VACUUM INTO writes a consistent, compact copy of the live database without closing it.
    try db.execute("VACUUM INTO ?", [.text(target.path)])
    // Optional: open the copy and check it before handing it over; delete it and throw if it is bad.
    return target
}
```

- **SQLite apps:** use `VACUUM INTO` (SQLite 3.27+, built into iOS). It takes a consistent snapshot even with the database
  open, and the copy needs no separate `-wal`/`-shm` files. Don't copy the `.sqlite` file directly while the app has it
  open, or you can get a half-written copy.
- **Core Data / SwiftData / JSON / CSV apps:** write the export file into the same kind of temporary folder and return
  its URL. Everything else stays the same.
- Give the file a clear name with its date and the right extension. The name and extension are what AirDrop, Drive and
  Files show.

### 2. A small wrapper around `UIActivityViewController`

```swift
import SwiftUI
import UIKit

/// The system share sheet (AirDrop, Messages, Save to Files, Google Drive, ...).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
```

Pass the **file `URL`**, not `Data`. A URL shares as a proper file with its name, so Google Drive and Files keep
`myapp-2026-11-19.sqlite`. `Data` can arrive unnamed or with the wrong type.

### 3. The button builds the file, then shows the sheet

```swift
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct BackupCard: View {
    @State private var shareItem: ShareItem?
    @State private var errorMessage: String?

    var body: some View {
        Button("Export database (.sqlite)") {
            do {
                shareItem = ShareItem(url: try exportDatabase())   // build the file first
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }   // then present the share sheet
    }
}
```

Use `.sheet(item:)` with an `Identifiable` wrapper, not `.sheet(isPresented:)` plus a separate URL variable. With
`item:` the sheet only opens once the file exists and always gets the right URL. With `isPresented:` the sheet can open
before the URL is set and come up empty.

## Optional extras this app also has

- **Last export date:** after a successful export, save today's date (e.g. `UserDefaults`) and show "Last export 19 Nov
  · 3 days ago". Turn it amber once a week has passed, as a reminder to back up.
- **The same pattern for any file:** this app reuses the same `ShareSheet` and `.sheet(item:)` for its markdown reports
  (diet review, labs review). Write the file to the temporary folder, then share its URL.

## Alternative on iOS 16+: `ShareLink`

SwiftUI's `ShareLink(item: url)` opens the same share sheet with no wrapper. It needs the URL **before** the button is
drawn, though. When the file is built at tap time, as with a database snapshot, use the `UIActivityViewController`
wrapper above.

## Checklist for the other app

- [ ] The Export button opens the share sheet directly, with no Files picker first.
- [ ] Nothing in the export path uses `.fileExporter` or `UIDocumentPickerViewController(forExporting:)`.
- [ ] The file is written to `temporaryDirectory`, with a dated name and the right extension.
- [ ] SQLite exports use `VACUUM INTO`, not a raw file copy.
- [ ] The file `URL` (not `Data`) goes to `UIActivityViewController`.
- [ ] `.sheet(item:)` with an `Identifiable` wrapper.
- [ ] On the phone: AirDrop, Save to Files and Google Drive all receive a file with the right name.

Reference implementation in this repo: `app/Support/Format.swift` (`ShareSheet`), `app/Screens/More/MoreTabView.swift`
(`export()`, `.sheet(item: $shareItem)`), `app/AppSession.swift` (`exportDatabase()`),
`src/modules/data/import-export-database/DatabaseFileService.swift` (`export(from:clock:to:)`, `VACUUM INTO`).
