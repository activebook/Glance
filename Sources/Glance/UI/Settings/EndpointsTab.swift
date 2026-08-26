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
            label: "OpenAI GPT-4o-mini",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            requiresKey: true
        ),
        ProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            icon: "bolt.fill",
            label: "DeepSeek Chat",
            baseURL: "https://api.deepseek.com",
            model: "deepseek-chat",
            requiresKey: true
        ),
        ProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            icon: "globe",
            label: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            model: "google/gemini-2.5-flash",
            requiresKey: true
        ),
        ProviderPreset(
            id: "ollama",
            name: "Ollama (Local)",
            icon: "macmini",
            label: "Ollama Local",
            baseURL: "http://localhost:11434/v1",
            model: "llama3.2-vision",
            requiresKey: false
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
                    Section("Quick Add Preset") {
                        ForEach(presets) { preset in
                            Button {
                                addPreset(preset)
                            } label: {
                                Label(preset.name, systemImage: preset.icon)
                            }
                        }
                    }
                    Divider()
                    Button("Custom AI Service…") {
                        addEndpoint()
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
        HStack(spacing: 8) {
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
        .padding(.vertical, 2)
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 36))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text(settings.endpoints.isEmpty ? "No AI Service Configured" : "No Service Selected")
                    .font(.system(size: 15, weight: .semibold))
                Text("Glance translates screen captures by connecting to OpenAI-compatible vision models.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Add Provider Preset:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(presets) { preset in
                        Button {
                            addPreset(preset)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 16))
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .frame(width: 80, height: 56)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.top, 4)

            Button("Add Custom Service") { addEndpoint() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
