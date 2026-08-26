import SwiftUI

/// AI Service management: NavigationSplitView master/detail with provider presets,
/// atomic draft-based editing, API key handling, and connection testing.
struct EndpointsTab: View {
    @ObservedObject var settings: SettingsStore

    // MARK: - Selection & draft state

    @State private var selectedID: UUID?
    @State private var draft = EndpointDraft()
    @State private var savedSnapshot = EndpointDraft()
    @State private var pendingDeletion: EndpointConfig?
    @State private var pendingNavigation: UUID?
    @State private var showUnsavedDialog = false
    @State private var showKey = false
    @State private var testState: TestState = .idle
    @State private var hoveredPresetID: String?

    enum TestState: Equatable {
        case idle
        case running
        case success(latencyMs: Int)
        case failure(String)

        var isRunning: Bool { self == .running }
    }

    struct EndpointDraft: Equatable {
        var label = ""
        var baseURLText = ""
        var model = ""
        var apiKey = ""
    }

    struct ProviderPreset: Identifiable {
        let id: String
        let name: String
        let icon: String
        let label: String
        let baseURL: String
        let model: String
        let requiresKey: Bool
    }

    private let presets: [ProviderPreset] = [
        ProviderPreset(
            id: "openai",
            name: "OpenAI",
            icon: "sparkles",
            label: "OpenAI (GPT-5.6 Luna)",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5.6-luna",
            requiresKey: true
        ),
        ProviderPreset(
            id: "google",
            name: "Google",
            icon: "brain",
            label: "Google Gemini Flash",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/",
            model: "gemini-flash-lite-latest",
            requiresKey: true
        ),
        ProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            icon: "bolt.fill",
            label: "DeepSeek V4 Flash Vision",
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-flash-vision-exp",
            requiresKey: true
        ),
        ProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            icon: "globe",
            label: "OpenRouter (Qwen 3.8)",
            baseURL: "https://openrouter.ai/api/v1",
            model: "qwen/qwen3.8-27b",
            requiresKey: true
        ),
        ProviderPreset(
            id: "ollama",
            name: "Ollama",
            icon: "macmini",
            label: "Ollama (Local)",
            baseURL: "http://localhost:11434/v1",
            model: "llama3.2-vision",
            requiresKey: false
        ),
        ProviderPreset(
            id: "custom",
            name: "Custom",
            icon: "slider.horizontal.3",
            label: "Custom AI Service",
            baseURL: "https://api.example.com/v1",
            model: "custom-model",
            requiresKey: true
        )
    ]

    private var selectedEndpoint: EndpointConfig? {
        settings.endpoints.first { $0.id == selectedID }
    }

    private var isDirty: Bool { draft != savedSnapshot }

    /// Validation of the draft as it would be saved.
    private var validationErrors: [EndpointConfig.ValidationError] {
        let candidate = EndpointConfig(
            label: draft.label,
            baseURL: URL(string: draft.baseURLText.trimmingCharacters(in: .whitespaces))
                ?? URL(string: "invalid://")!,
            model: draft.model
        )
        return candidate.validate()
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 300)
        .onAppear(perform: initialSelection)
        .onChange(of: selectedID) { _, newValue in
            guard let newValue else { return }
            handleSelectionChange(to: newValue)
        }
        .onChange(of: draft) { _, _ in
            if case .success = testState { testState = .idle }
            if case .failure = testState { testState = .idle }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.label ?? "")”?",
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete AI Service", role: .destructive) { confirmDeletion() }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Its stored API key will also be removed. This cannot be undone.")
        }
        .confirmationDialog(
            "Unsaved changes",
            isPresented: unsavedDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Save Changes") {
                saveDraft()
                proceedAfterGuard()
            }
            Button("Discard Changes", role: .destructive) {
                discardDraft()
                proceedAfterGuard()
            }
            Button("Cancel", role: .cancel) {
                selectedID = selectedID
                pendingNavigation = nil
            }
        } message: {
            Text("“\(selectedEndpoint?.label ?? "")” has edits that haven't been saved.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedID) {
            ForEach(settings.endpoints) { endpoint in
                row(for: endpoint)
                    .tag(endpoint.id)
                    .contextMenu {
                        Button(settings.defaultEndpointID == endpoint.id
                               ? "✓ Default Service" : "Set as Default") {
                            settings.setDefaultEndpoint(id: endpoint.id)
                        }
                        Button("Duplicate") { duplicate(endpoint) }
                        Divider()
                        Button("Delete…", role: .destructive) { pendingDeletion = endpoint }
                    }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 14) {
                Menu {
                    Section("Add AI Service") {
                        ForEach(presets) { preset in
                            Button {
                                addPreset(preset)
                            } label: {
                                Label {
                                    Text(preset.name)
                                } icon: {
                                    ProviderBrandIcon.image(for: preset.id, size: 14)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .help("Add AI Service")

                Button { duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(selectedEndpoint == nil)
                    .help("Duplicate selected service")

                Button(role: .destructive) {
                    if let endpoint = selectedEndpoint { pendingDeletion = endpoint }
                } label: { Image(systemName: "trash") }
                    .disabled(selectedEndpoint == nil)
                    .help("Delete selected service")

                Spacer()

                if let active = settings.activeEndpoint() {
                    Label(active.label, systemImage: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func row(for endpoint: EndpointConfig) -> some View {
        HStack(spacing: 10) {
            ProviderBrandIcon(providerID: detectProviderID(for: endpoint), size: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.label.isEmpty ? "(unnamed)" : endpoint.label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(hostDisplay(endpoint))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if settings.defaultEndpointID == endpoint.id {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                    .help("Default AI Service")
            }
        }
        .padding(.vertical, 3)
    }

    private func detectProviderID(for endpoint: EndpointConfig) -> String {
        let host = endpoint.baseURL.host?.lowercased() ?? ""
        if host.contains("openai.com") { return "openai" }
        if host.contains("googleapis.com") || host.contains("google") { return "google" }
        if host.contains("deepseek.com") { return "deepseek" }
        if host.contains("openrouter.ai") { return "openrouter" }
        if host.contains("localhost") || host.contains("127.0.0.1") { return "ollama" }
        return "custom"
    }

    private func hostDisplay(_ endpoint: EndpointConfig) -> String {
        var text = endpoint.baseURL.host ?? "invalid URL"
        if let port = endpoint.baseURL.port { text += ":\(port)" }
        return text
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if selectedEndpoint != nil {
            VStack(spacing: 0) {
                editorForm
                Divider()
                bottomBar
            }
        } else {
            emptyState
        }
    }

    private var editorForm: some View {
        Form {
            Section("AI Service Details") {
                LabeledContent("Service Name") {
                    TextField("", text: $draft.label)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Base URL") {
                    TextField("", text: $draft.baseURLText)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Model Name") {
                    TextField("", text: $draft.model)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                LabeledContent("API Key") {
                    HStack(spacing: 6) {
                        if showKey {
                            TextField("", text: $draft.apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("", text: $draft.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .help(showKey ? "Hide key" : "Show key")

                        Button("Paste") { pasteKey() }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("Stored securely in your macOS Keychain. Never transmitted anywhere except directly to your specified Base URL.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section {
                HStack(spacing: 10) {
                    Button("Test Connection") { runConnectionTest() }
                        .disabled(validationErrors.isEmpty == false || testState.isRunning)
                    if testState.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                switch testState {
                case .idle:
                    EmptyView()
                case .running:
                    Text("Connecting to AI endpoint…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                case .success(let latencyMs):
                    Label("Connected successfully · \(latencyMs) ms", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Connection Test")
            } footer: {
                Text("Tests the live vision API endpoint using the values above.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var validationSummary: some View {
        if isDirty {
            if validationErrors.isEmpty {
                Label("Looks good — ready to save", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(validationErrors, id: \.self) { error in
                        Label(error.errorDescription ?? "", systemImage: "exclamationmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            validationSummary
            Spacer()
            if isDirty {
                Text("Unsaved changes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Revert") { discardDraft() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { saveDraft() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!validationErrors.isEmpty)
            } else if !validationErrors.isEmpty {
                Text("This service has errors — please fix before saving.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.15), value: isDirty)
    }

    // MARK: - Empty State (Onboarding Card Grid)

    private var emptyState: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                }

                Text(settings.endpoints.isEmpty ? "Connect an AI Service" : "No Service Selected")
                    .font(.system(size: 17, weight: .bold))

                Text("Choose an AI provider below to set up high-accuracy screen translation.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // 2 x 3 Card Grid
            LazyVGrid(
                columns: [
                    GridItem(.fixed(136), spacing: 14),
                    GridItem(.fixed(136), spacing: 14),
                    GridItem(.fixed(136), spacing: 14)
                ],
                spacing: 14
            ) {
                ForEach(presets) { preset in
                    presetCard(preset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func presetCard(_ preset: ProviderPreset) -> some View {
        Button {
            addPreset(preset)
        } label: {
            VStack(spacing: 7) {
                ProviderBrandIcon(providerID: preset.id, size: 28)

                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(preset.model)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 136, height: 88)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        hoveredPresetID == preset.id ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.6),
                        lineWidth: hoveredPresetID == preset.id ? 1.5 : 1
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredPresetID = isHovered ? preset.id : nil
            }
        }
    }

    // MARK: - Draft lifecycle

    private func loadDraft(from endpoint: EndpointConfig?) {
        guard let endpoint else {
            draft = EndpointDraft()
            savedSnapshot = EndpointDraft()
            return
        }
        draft = EndpointDraft(
            label: endpoint.label,
            baseURLText: endpoint.baseURL.absoluteString,
            model: endpoint.model,
            apiKey: settings.key(for: endpoint.id) ?? ""
        )
        savedSnapshot = draft
        showKey = false
        testState = .idle
    }

    private func saveDraft() {
        guard var endpoint = selectedEndpoint else { return }
        endpoint.label = draft.label.trimmingCharacters(in: .whitespaces)
        endpoint.baseURL = URL(string: draft.baseURLText.trimmingCharacters(in: .whitespaces))
            ?? endpoint.baseURL
        endpoint.model = draft.model.trimmingCharacters(in: .whitespaces)
        settings.updateEndpoint(endpoint)
        settings.setKey(draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        for: endpoint.id)
        savedSnapshot = draft
    }

    private func discardDraft() {
        loadDraft(from: selectedEndpoint)
    }

    // MARK: - Actions & guards

    private func initialSelection() {
        if selectedID == nil {
            selectedID = settings.endpoints.first?.id
            loadDraft(from: selectedEndpoint)
        }
    }

    private func handleSelectionChange(to newID: UUID) {
        if isDirty && pendingNavigation != newID {
            pendingNavigation = newID
            showUnsavedDialog = true
        } else {
            loadDraft(from: settings.endpoints.first { $0.id == newID })
        }
    }

    private var unsavedDialogBinding: Binding<Bool> {
        Binding(
            get: { showUnsavedDialog },
            set: { shown in
                showUnsavedDialog = shown
                if !shown && pendingNavigation != nil {
                    selectedID = selectedID
                    pendingNavigation = nil
                }
            }
        )
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func proceedAfterGuard() {
        if let target = pendingNavigation {
            loadDraft(from: settings.endpoints.first { $0.id == target })
        }
        pendingNavigation = nil
    }

    private func confirmDeletion() {
        guard let endpoint = pendingDeletion else { return }
        let wasSelected = endpoint.id == selectedID
        settings.deleteEndpoint(id: endpoint.id)
        if wasSelected {
            selectedID = nil
            selectedID = settings.endpoints.first?.id
            loadDraft(from: selectedEndpoint)
        }
        pendingDeletion = nil
    }

    // MARK: - CRUD helpers

    private func addPreset(_ preset: ProviderPreset) {
        let endpoint = EndpointConfig(
            label: preset.label,
            baseURL: URL(string: preset.baseURL) ?? EndpointConfig.exampleBaseURL,
            model: preset.model
        )
        settings.addEndpoint(endpoint, key: nil)
        selectedID = endpoint.id
        loadDraft(from: endpoint)
    }

    private func addEndpoint() {
        let endpoint = EndpointConfig(label: EndpointConfig.exampleLabel,
                                      baseURL: EndpointConfig.exampleBaseURL,
                                      model: EndpointConfig.exampleModel)
        settings.addEndpoint(endpoint, key: nil)
        selectedID = endpoint.id
        loadDraft(from: endpoint)
    }

    private func duplicate(_ source: EndpointConfig) {
        let copy = EndpointConfig(label: source.label + " copy",
                                  baseURL: source.baseURL,
                                  model: source.model)
        settings.addEndpoint(copy, key: nil)
        selectedID = copy.id
        loadDraft(from: copy)
    }

    private func duplicateSelected() {
        guard let source = selectedEndpoint else { return }
        duplicate(source)
    }

    private func pasteKey() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        draft.apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Connection test

    private func runConnectionTest() {
        guard let baseURL = URL(string: draft.baseURLText.trimmingCharacters(in: .whitespaces)) else {
            testState = .failure("Base URL is not valid.")
            return
        }
        let model = draft.model.trimmingCharacters(in: .whitespaces)
        let apiKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        testState = .running

        Task {
            let outcome = await LLMClient.testConnection(baseURL: baseURL,
                                                         apiKey: apiKey,
                                                         model: model)
            await MainActor.run {
                guard testState.isRunning else { return }
                switch outcome {
                case .success(let ms): testState = .success(latencyMs: ms)
                case .failure(let msg): testState = .failure(msg)
                }
            }
        }
    }
}
