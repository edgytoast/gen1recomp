//  Getting a cartridge dump into the app.
//
//  The engine finds a ROM by scanning its own save directory for a .gb/.gbc,
//  preferring one called picked_rom.gb (src/import/RomImporter.lua). So this
//  does not need a bridge into LÖVE at all: copy the file the player chose to
//  that name and the importer picks it up, verifies its SHA-1 and decodes it.
//
//  On iOS the engine reaches a picker through love.system.pickFile, a native
//  bridge in the LÖVE tree. Doing the same here would mean porting that bridge
//  and the SwiftUI shell would still have to own the picker, so this is the
//  shorter path to the same place.

import SwiftUI
import UniformTypeIdentifiers

enum GRRomImport {

    /// LÖVE's save directory: `Library/Application Support/<identity>`.
    ///
    /// NOT Documents. On Apple platforms LÖVE resolves COMMONPATH_APP_SAVEDIR
    /// from COMMONPATH_USER_APPDATA, which is Application Support
    /// (Filesystem.cpp; apple::USER_DIRECTORY_APPSUPPORT), and appends the
    /// identity directly because the game is fused. Assuming the iOS
    /// Documents convention instead put a ROM somewhere the engine never
    /// looks, and it reported "no ROM imported" while the file sat there.
    static var saveDirectory: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first
        else { return nil }
        return support.appendingPathComponent("pokemon-love2d", isDirectory: true)
    }

    static var romPresent: Bool {
        guard let dir = saveDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return false }
        return names.contains { $0.lowercased().hasSuffix(".gb") || $0.lowercased().hasSuffix(".gbc") }
    }

    /// Copies a picked file in as picked_rom.gb. Returns a message to show.
    static func accept(_ source: URL) -> String {
        guard let dir = saveDirectory else { return "No save directory." }

        // A file from the document picker lives outside the sandbox until
        // asked for; without this the read fails with a permission error that
        // looks like a missing file.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try Data(contentsOf: source)
            // Named picked_rom.gb because that is what the importer looks for
            // first; the extension does not have to match the original, since
            // the engine identifies the ROM by SHA-1 rather than by name.
            let dest = dir.appendingPathComponent("picked_rom.gb")
            try data.write(to: dest, options: .atomic)
            return "Imported \(source.lastPathComponent) (\(data.count / 1024) KB). Restart to decode it."
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
    }

    /// .gb and .gbc are not system-declared types, so they are matched by
    /// filename extension.
    static var contentTypes: [UTType] {
        [UTType(filenameExtension: "gb"), UTType(filenameExtension: "gbc")]
            .compactMap { $0 } + [.data]
    }

    // MARK: - The Stadium cartridge
    //
    // The mod's 3D battlers are Pokemon Stadium's own models, so the mod
    // ships none and the player supplies the cartridge.  It looks for one
    // under `baseroms/` on the read path and builds its packs from whatever
    // it finds there (lib/StadiumInstall).
    //
    // Its own importer opens a file dialog through a shell -- osascript,
    // PowerShell, zenity -- and there is no shell here, so on this platform
    // that row cannot do anything.  On Quest the launcher owns the import
    // instead (lib/QuestLauncher), and that file is Quest-specific and was
    // left out of the port: this is the same job for the launcher we do have.
    //
    // The last metre only.  Nothing here validates the cartridge or builds a
    // model: the mod already does both, says so on its own screen, and doing
    // it twice in two languages is how the two answers come to disagree.

    /// `baseroms/` under the save directory -- the one place that is always
    /// writable and always on the read path (StadiumInstall.romHint says so
    /// itself, and it is what a packaged build needs).
    static var stadiumDirectory: URL? {
        saveDirectory?.appendingPathComponent("baseroms", isDirectory: true)
    }

    private static let stadiumExtensions = ["z64", "n64", "v64"]

    /// The cartridge's own name, if one is in: the mod matches by extension
    /// (`%.[nvz]64$`), so this asks the same question the same way.
    static var stadiumRomName: String? {
        guard let dir = stadiumDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return nil }
        return names.sorted().first { name in
            stadiumExtensions.contains((name as NSString).pathExtension.lowercased())
        }
    }

    /// Copies a picked cartridge into `baseroms/`, under its own name.
    ///
    /// Under its OWN name, not a fixed one: the mod scans the folder rather
    /// than looking for a particular file, and a name the player recognises
    /// is what makes "which cartridge is in?" answerable at a glance.
    static func acceptStadium(_ source: URL) -> String {
        guard let dir = stadiumDirectory else { return "No save directory." }
        let ext = source.pathExtension.lowercased()
        guard stadiumExtensions.contains(ext) else {
            return "That is not an N64 cartridge (.z64, .n64 or .v64)."
        }

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try Data(contentsOf: source)
            let dest = dir.appendingPathComponent(source.lastPathComponent)
            try data.write(to: dest, options: .atomic)
            return "Imported \(source.lastPathComponent) (\(data.count / 1024 / 1024) MB). "
                 + "The models build in game, on the loading screen."
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
    }

    /// How many model packs have been built out of it.
    ///
    /// Read, not inferred: a cartridge sitting in the folder says nothing
    /// about whether anything came of it, and "imported" with no models is
    /// exactly the state a player would otherwise have no way to see.  The
    /// mod writes one .dsm per species into dramatic_shape/stadium.
    static var stadiumPackCount: Int {
        guard let dir = saveDirectory?
                .appendingPathComponent("dramatic_shape", isDirectory: true)
                .appendingPathComponent("stadium", isDirectory: true),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return 0 }
        return names.filter { $0.lowercased().hasSuffix(".dsm") }.count
    }

    static var stadiumContentTypes: [UTType] {
        stadiumExtensions.compactMap { UTType(filenameExtension: $0) } + [.data]
    }
}
