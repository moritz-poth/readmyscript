import ScriptCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var dropping = false
    private var dark: Bool { settings.dark }
    var theme: Theme { Theme(dark: dark) }

    var body: some View {
        VStack(spacing: 0) {
            UpdateBanner(theme: theme)
            header
            if model.analyticsOn {
                Notice(theme: theme, text: Text("VoiceStudio sends usage statistics. Switch them off in VoiceStudio's settings before you read a script."))
                    .padding(.horizontal, 20).padding(.bottom, 12)
            }
            if model.cloudSyncOn {
                Notice(theme: theme, text: Text("VoiceStudio's cloud sync is on: voice names and settings leave this Mac. Switch it off in VoiceStudio before you read a script."))
                    .padding(.horizontal, 20).padding(.bottom, 12)
            }
            if let script = model.script {
                HStack(alignment: .top, spacing: 16) {
                    CastPanel(model: model, script: script, theme: theme).frame(width: 400)
                    ScriptPreview(model: model, script: script, theme: theme)
                }
                .padding(.horizontal, 20)
                footer(script)
            } else {
                dropZone
            }
        }
        .background(theme.background)
        .foregroundColor(theme.text)
        .font(.mono(12))
        .preferredColorScheme(dark ? .dark : .light)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in model.open(url) }
            }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(verbatim: "READ MY SCRIPT")
                .font(.custom("HelveticaNeue-Light", size: 18)).tracking(4)
            if let s = model.script {
                Text(s.title).foregroundColor(theme.muted).lineLimit(1).truncationMode(.middle)
                if !model.busy {
                    Button { model.close() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                        .buttonStyle(FerryButtonStyle(theme: theme, height: 22))
                        .help(Text("Close script")).accessibilityLabel(Text("Close script"))
                }
            }
            Spacer()
            StudioStatus(model: model, theme: theme)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text").font(.system(size: 34, weight: .ultraLight)).foregroundColor(theme.muted)
            Text("Drop a screenplay PDF here").font(.mono(15))
            Text("The script stays on this Mac: it only goes to VoiceStudio on this computer.")
                .foregroundColor(theme.faint).multilineTextAlignment(.center)
            Button("Open PDF…") { openPanel(model) }.buttonStyle(FerryButtonStyle(theme: theme, primary: true))
            if let e = model.openError { Text(e).foregroundColor(theme.warning) }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(dropping ? theme.muted : theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])).padding(20))
    }

    @ViewBuilder private func footer(_ script: Script) -> some View {
        HStack(spacing: 12) {
            Text("Voice language").foregroundColor(theme.muted)
            Dropdown(title: Text(languageName(model.language)), theme: theme) {
                ForEach([nil, "German", "English"], id: \.self) { l in
                    Button(languageName(l)) { model.language = l }.disabled(l == model.language)
                }
            }
            .disabled(model.busy)
            Spacer()
            progress
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func languageName(_ l: String?) -> LocalizedStringKey {
        switch l { case "German": return "Deutsch"; case "English": return "English"; default: return "Automatic" }
    }

    @ViewBuilder private var progress: some View {
        switch model.phase {
        case .idle:
            let spans = model.plan?.spanCount ?? 0
            let open = model.script.map { model.cast.unassigned(in: $0).count } ?? 0
            if open > 0 {
                Text(open == 1 ? "1 role has no voice yet." : "\(open) roles have no voice yet.").foregroundColor(theme.warning)
            }
            Button("Create Audiobook…") { savePanel(model) }
                .buttonStyle(FerryButtonStyle(theme: theme, primary: true))
                .disabled(!model.studioReady || spans == 0 || open > 0)
        case .rendering(let done, let total, let assembling):
            ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 180)
            Text(assembling ? "Putting the audiobook together…" : "Scene \(min(done + 1, total)) of \(total)")
                .foregroundColor(theme.muted).monospacedDigit()
            Button("Pause") { model.pause() }.buttonStyle(FerryButtonStyle(theme: theme)).disabled(assembling)
            Button("Cancel") { model.cancel() }.buttonStyle(FerryButtonStyle(theme: theme))
        case .paused(let done, let total):
            Text("Paused – \(done) of \(total) scenes done").foregroundColor(theme.muted).monospacedDigit()
            Button("Resume") { model.resume() }.buttonStyle(FerryButtonStyle(theme: theme, primary: true)).disabled(!model.studioReady)
            Button("Cancel") { model.cancel() }.buttonStyle(FerryButtonStyle(theme: theme))
        case .finished(let url, let failed):
            (failed == 0 ? Text("Saved: \(url.lastPathComponent)") : Text("Saved with \(failed) missing scenes: \(url.lastPathComponent)"))
                .foregroundColor(failed == 0 ? theme.text : theme.warning).lineLimit(1).truncationMode(.middle)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(FerryButtonStyle(theme: theme))
            Button("Create Again…") { savePanel(model) }.buttonStyle(FerryButtonStyle(theme: theme)).disabled(!model.studioReady)
        case .failed(let msg):
            Text(msg).foregroundColor(theme.warning).lineLimit(2)
            Button("Try Again…") { savePanel(model) }.buttonStyle(FerryButtonStyle(theme: theme, primary: true)).disabled(!model.studioReady)
        }
    }
}

struct StudioStatus: View {
    @ObservedObject var model: AppModel
    let theme: Theme
    var body: some View {
        HStack(spacing: 8) {
            // filled dot = ready, ring = not running (not by colour alone)
            Circle().fill(model.studioReady ? theme.online : .clear)
                .overlay(Circle().stroke(model.studioReady ? theme.online : theme.faint, lineWidth: 1.5))
                .frame(width: 8, height: 8)
            Text(model.studioReady ? "VoiceStudio ready" : "VoiceStudio is not running").foregroundColor(theme.muted)
            if !model.studioReady {
                Button("Start VoiceStudio") { model.launchStudio() }.buttonStyle(FerryButtonStyle(theme: theme))
            }
        }
    }
}

struct Notice: View {
    let theme: Theme
    let text: Text
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundColor(theme.warning)
            text.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.warning, lineWidth: 1))
    }
}

// MARK: - Cast

struct CastPanel: View {
    @ObservedObject var model: AppModel
    let script: Script
    let theme: Theme
    @State private var designing: Designing?

    struct Designing: Identifiable { var role: String?; var id: String { role ?? "" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CAST").font(.mono(11, semibold: true)).foregroundColor(theme.muted)
                Spacer()
                Text("\(script.sceneCount) scenes · \(script.roles.count) roles").foregroundColor(theme.faint)
            }
            .padding(12)
            if script.skippedBeforeFirstScene > 0 {
                Text("\(script.skippedBeforeFirstScene) paragraphs before the first scene heading are not read.")
                    .font(.mono(10)).foregroundColor(theme.warning).padding(.horizontal, 12).padding(.bottom, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(theme.line)
            row(name: Text("Narrator"), detail: Text("Action"), role: nil)
            Divider().overlay(theme.line)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(script.roles, id: \.name) { r in
                        row(name: Text(verbatim: r.name), detail: r.lines == 1 ? Text("1 line") : Text("\(r.lines) lines"), role: r.name)
                    }
                }
            }
            if model.voices.isEmpty {
                Text(model.studioReady ? "VoiceStudio has no voices yet. Create some in VoiceStudio first." : "Start VoiceStudio to choose voices.")
                    .foregroundColor(theme.faint).padding(12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
        .disabled(model.busy)
        .sheet(item: $designing) { d in DesignSheet(model: model, role: d.role, theme: theme) }
    }

    private func voice(_ role: String?) -> String? { role.map { model.cast.roles[$0] ?? nil } ?? model.cast.narrator }
    /// A role without any choice yet (neither a voice nor "Don't read").
    private func unassigned(_ role: String?) -> Bool { role.map { model.cast.roles[$0] == nil } ?? false }

    private func title(_ role: String?, _ current: String?) -> Text {
        if let name = model.voiceName(current) { return Text(verbatim: name).foregroundColor(theme.text) }
        return unassigned(role) ? Text("Choose Voice").foregroundColor(theme.warning) : Text("Not read").foregroundColor(theme.faint)
    }

    /// "Anna" or "Narrator, BEN" – who already uses this voice, for the menu.
    private func usersLabel(_ voice: String, except role: String?) -> String? {
        let u = model.cast.users(of: voice, except: role)
        return u.isEmpty ? nil : u.map { $0.isEmpty ? String(localized: "Narrator") : $0 }.joined(separator: ", ")
    }

    private func row(name: Text, detail: Text, role: String?) -> some View {
        let current = voice(role)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                name.lineLimit(1).truncationMode(.middle)
                detail.font(.mono(10)).foregroundColor(theme.faint)
            }
            Spacer(minLength: 8)
            Dropdown(title: title(role, current), theme: theme) {
                Button("Don't read") { set(role, nil) }.disabled(current == nil && !unassigned(role))
                Divider()
                ForEach(model.voices) { v in
                    // a voice someone else already speaks with is marked; taking it needs a confirmation
                    if let users = usersLabel(v.id, except: role) {
                        Button("\(v.name) – \(users)") { set(role, v.id) }.disabled(v.id == current)
                    } else {
                        Button(v.name) { set(role, v.id) }.disabled(v.id == current)
                    }
                }
                Divider()
                Button("New Voice…") { designing = Designing(role: role) }.disabled(!model.studioReady)
            }
            Button { model.preview(role: role) } label: {
                Image(systemName: model.previewing == (role ?? "") ? "waveform" : "play.fill").font(.system(size: 9))
                    .frame(width: 10)
            }
            .buttonStyle(FerryButtonStyle(theme: theme))
            .disabled(current == nil || !model.studioReady || model.previewing != nil)
            .help(Text("Listen")).accessibilityLabel(Text("Listen"))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private func set(_ role: String?, _ id: String?) {
        if let id, let users = usersLabel(id, except: role), !confirmShare(voice: model.voiceName(id) ?? id, users: users, role: role) { return }
        if let role { model.cast.roles[role] = .some(id) } else { model.cast.narrator = id }
    }

    /// Two parts with one voice are hard to tell apart – only when the user really wants it.
    private func confirmShare(voice: String, users: String, role: String?) -> Bool {
        let a = NSAlert()
        a.messageText = String(localized: "“\(voice)” already speaks \(users).")
        let part = role ?? String(localized: "Narrator")
        a.informativeText = String(localized: "Listeners tell the roles apart by their voices only. Use this voice for \(part) as well?")
        a.addButton(withTitle: String(localized: "Use Voice Twice"))
        a.addButton(withTitle: String(localized: "Cancel"))
        return a.runModal() == .alertFirstButtonReturn
    }
}

/// Builds a new voice in VoiceStudio from attributes: listen, try other variants, save.
struct DesignSheet: View {
    @ObservedObject var model: AppModel
    let role: String?
    let theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var design = VoiceDesign()
    @State private var name = ""
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Voice").font(.mono(14, semibold: true))
            Text("VoiceStudio builds the voice from these traits, on this Mac.").foregroundColor(theme.muted)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Gender").foregroundColor(theme.muted)
                    picker(VoiceDesign.Gender.allCases, \.gender) { $0 == .male ? "Male" : "Female" }
                }
                GridRow {
                    Text("Age").foregroundColor(theme.muted)
                    picker(VoiceDesign.Age.allCases, \.age) {
                        switch $0 { case .child: "Child"; case .teenager: "Teenager"; case .youngAdult: "Young adult"
                        case .middleAged: "Middle-aged"; case .elderly: "Elderly" }
                    }
                }
                GridRow {
                    Text("Pitch").foregroundColor(theme.muted)
                    picker(VoiceDesign.Pitch.allCases, \.pitch) {
                        switch $0 { case .veryLow: "Very low"; case .low: "Low"; case .moderate: "Medium"
                        case .high: "High"; case .veryHigh: "Very high" }
                    }
                }
                GridRow {
                    Text("Whisper").foregroundColor(theme.muted)
                    Switch(on: design.whisper, theme: theme) { design.whisper.toggle() }
                }
                GridRow {
                    Text("Name").foregroundColor(theme.muted)
                    TextField("", text: $name).textFieldStyle(.roundedBorder).frame(width: 220)
                }
            }
            HStack(spacing: 8) {
                Button { model.preview(role: role, design: design) } label: {
                    Label(model.previewing != nil ? "Listening…" : "Listen", systemImage: model.previewing != nil ? "waveform" : "play.fill")
                }
                .buttonStyle(FerryButtonStyle(theme: theme)).disabled(model.previewing != nil)
                Button("Other Variant") { design.seed = Int.random(in: 1...99_999); model.preview(role: role, design: design) }
                    .buttonStyle(FerryButtonStyle(theme: theme)).disabled(model.previewing != nil)
                    .help(Text("Same traits, a different voice"))
            }
            if failed { Text("VoiceStudio could not save the voice. See the log file.").foregroundColor(theme.warning) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(FerryButtonStyle(theme: theme)).keyboardShortcut(.cancelAction)
                Button("Save Voice") {
                    saving = true
                    Task {
                        if await model.createVoice(design, name: name.trimmingCharacters(in: .whitespaces), for: role) { dismiss() }
                        else { failed = true; saving = false }
                    }
                }
                .buttonStyle(FerryButtonStyle(theme: theme, primary: true)).keyboardShortcut(.defaultAction)
                .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty || !model.studioReady)
            }
        }
        .padding(20).frame(width: 440)
        .background(theme.background).foregroundColor(theme.text).font(.mono(12))
        .onAppear { name = role.map { $0.capitalized } ?? String(localized: "Narrator") }
    }

    private func picker<V: Hashable>(_ all: [V], _ key: WritableKeyPath<VoiceDesign, V>, _ label: @escaping (V) -> LocalizedStringKey) -> some View {
        Dropdown(title: Text(label(design[keyPath: key])), theme: theme) {
            ForEach(all, id: \.self) { v in Button(label(v)) { design[keyPath: key] = v }.disabled(v == design[keyPath: key]) }
        }
    }
}

// MARK: - Script preview

struct ScriptPreview: View {
    @ObservedObject var model: AppModel
    let script: Script
    let theme: Theme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(script.elements) { e in line(e) }
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder private func line(_ e: Element) -> some View {
        let voice = model.cast.voice(for: e)
        let spoken = voice != nil
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                switch e.kind {
                case .scene: Text(verbatim: e.text).font(.mono(12, semibold: true)).padding(.top, 10)
                case .character: Text(verbatim: e.text).padding(.leading, 140).padding(.top, 4)
                case .parenthetical: Text(verbatim: e.text).padding(.leading, 110)
                case .dialogue: Text(verbatim: e.text).padding(.leading, 70).padding(.trailing, 40)
                case .transition: Text(verbatim: e.text).frame(maxWidth: .infinity, alignment: .trailing)
                case .action: Text(verbatim: e.text)
                }
            }
            .foregroundColor(spoken || e.kind == .scene || e.kind == .character ? theme.text : theme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: model.voiceName(voice) ?? "")
                .font(.mono(10)).foregroundColor(theme.faint).frame(width: 90, alignment: .trailing).lineLimit(1)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if e.kind != .scene && e.kind != .character {
                Button("Read by narrator") { model.setOverride(e.id, .narrator) }
                Button("Don't read") { model.setOverride(e.id, .silent) }
                if model.cast.overrides[e.id] != nil { Divider(); Button("As detected") { model.setOverride(e.id, nil) } }
            }
        }
    }
}

// MARK: - Panels

@MainActor func openPanel(_ model: AppModel) {
    let p = NSOpenPanel()
    p.allowedContentTypes = [.pdf]
    if p.runModal() == .OK, let url = p.url { model.open(url) }
}

@MainActor func savePanel(_ model: AppModel) {
    let p = NSSavePanel()
    p.allowedContentTypes = [UTType(filenameExtension: "m4b") ?? .audio]
    p.nameFieldStringValue = model.suggestedFileName()
    p.directoryURL = model.pdf?.deletingLastPathComponent()
    if p.runModal() == .OK, let url = p.url { model.create(to: url) }
}
