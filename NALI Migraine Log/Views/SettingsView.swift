import SwiftUI
import CoreLocation
import UniformTypeIdentifiers
import PDFKit

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingMigrationAlert = false
    @State private var showingMigrationError = false
    @State private var migrationErrorMessage = ""
    @State private var showingExportError = false
    @State private var exportErrorMessage = ""
    @State private var showingLocationAlert = false
    @State private var isBackfilling = false
    @State private var backfillProgress = 0
    @State private var backfillTotal = 0
    @State private var showingBackfillAlert = false
    @State private var backfillResult = ""

    // Recovery file states — surfaces `PersistenceController.lastRecoveryFileDefaultsKey`
    // when a corrupted Core Data store has been moved aside, so the user can
    // share it with support before the OS reclaims temp/Documents storage.
    @State private var recoveryFileURL: URL?
    @State private var recoveryFileModificationDate: Date?
    @State private var recoveryFileSizeBytes: Int64?
    @State private var showingRecoveryShareSheet = false
    @State private var showingRecoveryDismissConfirm = false

    // Export states
    @State private var showingExportWarning = false
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var exportFormat: ExportFormat = .csv

    // Help & Feedback — drives the in-app feedback sheet. The "Rate
    // on App Store" button doesn't need a state var because it's a
    // straight `Link` to the App Store deep link.
    @State private var showingFeedbackForm = false

    // Apple Health mirroring. The toggle is bound directly through
    // `HealthKitManager.shared.isHealthSyncEnabled` (which persists to
    // UserDefaults on every change), so we only need local state for the
    // backfill progress and the post-backfill alert.
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var isHealthBackfilling = false
    @State private var showingHealthBackfillAlert = false
    @State private var healthBackfillResult = ""

    // Notifications. Both toggles are bound through `NotificationManager`
    // (which persists to UserDefaults on every change and triggers the
    // appropriate cancel/reschedule). `showingNotificationDeniedAlert`
    // surfaces the iOS Settings deep link when the user toggles ON but
    // the system already denied permission in a prior run.
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingNotificationDeniedAlert = false
    
    /// Drives the two-pane settings layout on iPad. Compact (iPhone)
    /// keeps the long single-form scroll users have always known.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    /// Currently-selected category in the iPad two-pane layout. Backed
    /// by `@State` so it sticks across view rebuilds while the sheet
    /// is open (a sheet's lifetime, not a rebuilding child of MigraineLogView).
    @State private var selectedCategory: SettingsCategory = .sync
    
    /// One-to-one with the existing `*Section` computed properties.
    /// The iPhone layout still concatenates them in a single Form;
    /// the iPad layout drives them through a sidebar list selection.
    /// Adding a new section: drop a case here, give it a title +
    /// SF Symbol, and route it in `iPadDetailContent(for:)`. The
    /// iPhone form picks it up only if you also append it to the body.
    enum SettingsCategory: Hashable, CaseIterable, Identifiable {
        case recovery
        case sync
        case weather
        case notifications
        case health
        case appearance
        case units
        case export
        case feedback
        
        var id: Self { self }
        
        var title: String {
            switch self {
            case .recovery:      return "Database Recovery"
            case .sync:          return "Sync & iCloud"
            case .weather:       return "Weather"
            case .notifications: return "Notifications"
            case .health:        return "Apple Health"
            case .appearance:    return "Appearance"
            case .units:         return "Units"
            case .export:        return "Export Data"
            case .feedback:      return "Help & Feedback"
            }
        }
        
        var systemImage: String {
            switch self {
            case .recovery:      return "exclamationmark.shield.fill"
            case .sync:          return "icloud"
            case .weather:       return "cloud.sun"
            case .notifications: return "bell.badge"
            case .health:        return "heart.text.square"
            case .appearance:    return "paintbrush"
            case .units:         return "ruler"
            case .export:        return "square.and.arrow.up"
            case .feedback:      return "questionmark.circle"
            }
        }
        
        /// Tint color for the SF Symbol in the iPad sidebar list. Keeps
        /// the destinations visually distinct at a glance instead of an
        /// all-blue uniform stack.
        var tint: Color {
            switch self {
            case .recovery:      return .orange
            case .sync:          return .blue
            case .weather:       return .cyan
            case .notifications: return .red
            case .health:        return .pink
            case .appearance:    return .purple
            case .units:         return .indigo
            case .export:        return .teal
            case .feedback:      return .green
            }
        }
    }
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case pdf = "PDF"
    }

    /// Trigger column order for the CSV export. Locked to match the literal
    /// header string in `exportToCSV()` — DO NOT reorder without also
    /// updating the header, or downstream parsers will silently misalign.
    fileprivate static let csvTriggerOrder: [MigraineTrigger] = [
        .stress, .lackOfSleep, .dehydration, .weather, .menstrual,
        .alcohol, .caffeine, .food, .exercise, .screenTime, .other
    ]

    /// Medication column order for the CSV export. Locked to match the literal
    /// header string in `exportToCSV()`. Excludes `.eletriptan` to preserve
    /// byte-for-byte compatibility with previously exported CSVs.
    fileprivate static let csvMedicationOrder: [MigraineMedication] = [
        .ibuprofin, .excedrin, .tylenol, .sumatriptan, .rizatriptan,
        .naproxen, .frovatriptan, .naratriptan, .nurtec, .symbravo,
        .ubrelvy, .reyvow, .trudhesa, .elyxyb, .other
    ]
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadBody
            } else {
                iPhoneBody
            }
        }
        .alert("Data Migration", isPresented: $showingMigrationAlert) {
                Button("Cancel") {
                    settings.useICloudSync = false
                }
                Button("Migrate") {
                    Task {
                        await performMigration()
                    }
                }
            } message: {
                Text("Your data needs to be migrated to enable iCloud sync. This may take a few moments.")
            }
            .alert("Migration Error", isPresented: $showingMigrationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(migrationErrorMessage)
            }
            .alert("Export Error", isPresented: $showingExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportErrorMessage)
            }
            .alert("Location Services", isPresented: $showingLocationAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("Location access is currently disabled. To enable weather tracking, please allow location access in Settings.")
            }
            .alert("Backfill Complete", isPresented: $showingBackfillAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(backfillResult)
            }
            .alert("Export Health Data", isPresented: $showingExportWarning) {
                Button("Cancel", role: .cancel) { }
                Button("I Understand, Export") {
                    Task {
                        await performExport()
                    }
                }
            } message: {
                Text("⚠️ IMPORTANT: Your exported data will NOT be encrypted.\n\nThis file will contain sensitive health information including:\n• Migraine dates and times\n• Pain levels and symptoms\n• Medications taken\n• Personal notes\n• Location/weather data\n\nOnly share this file with trusted healthcare providers. Delete the file after use to protect your privacy.")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showingRecoveryShareSheet) {
                if let url = recoveryFileURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showingFeedbackForm) {
                FeedbackFormView(origin: .settings)
            }
            .confirmationDialog(
                "Dismiss recovered database notice?",
                isPresented: $showingRecoveryDismissConfirm,
                titleVisibility: .visible
            ) {
                Button("Dismiss Notice", role: .destructive) {
                    dismissRecoveryNotice()
                }
                Button("Keep Notice", role: .cancel) { }
            } message: {
                Text("The backup file will remain on disk and can be shared from the Files app, but this notice will not appear here again.")
            }
            .onAppear {
                AppLogger.ui.debug("SettingsView appeared; location status raw=\(locationManager.authorizationStatus.rawValue, privacy: .public)")
                locationManager.refreshAuthorizationStatus()
                refreshRecoveryFileMetadata()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                AppLogger.ui.debug("App entering foreground; refreshing location status")
                locationManager.refreshAuthorizationStatus()
                refreshRecoveryFileMetadata()
            }
    }
    
    // MARK: - iPhone (compact) — single-form layout
    
    /// Single scrollable Form, identical to the iPhone layout that's
    /// shipped since v1. Keeps `recoverySection` first so a corrupt-
    /// store notice catches the user's eye before routine settings.
    private var iPhoneBody: some View {
        NavigationView {
            Form {
                recoverySection
                dataSyncSection
                weatherTrackingSection
                backfillSection
                unitsSection
                appearanceSection
                notificationsSection
                appleHealthSection
                exportSection
                feedbackSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - iPad (regular) — two-pane layout
    
    /// Sidebar on the left lists every visible category; the detail
    /// pane on the right wraps the matching `*Section` view in a Form
    /// so the section's existing styling (grouped rows, headers,
    /// footers, validation alerts) carries over unchanged. Each
    /// category is one-to-one with an existing iPhone form section
    /// — see `SettingsCategory` for the full mapping.
    private var iPadBody: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { Optional(selectedCategory) },
                set: { newValue in
                    if let value = newValue { selectedCategory = value }
                }
            )) {
                ForEach(visibleCategories) { category in
                    NavigationLink(value: category) {
                        Label {
                            Text(category.title)
                        } icon: {
                            Image(systemName: category.systemImage)
                                .foregroundColor(category.tint)
                        }
                    }
                    .tag(category)
                }
            }
            .navigationTitle("Settings")
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        } detail: {
            iPadDetailContent(for: selectedCategory)
                .navigationTitle(selectedCategory.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    /// The visible category list adapts to runtime state — `.recovery`
    /// only appears when there's an active backup file on disk so users
    /// without one don't get a confusing "Database Recovery" entry.
    private var visibleCategories: [SettingsCategory] {
        var cats: [SettingsCategory] = []
        if recoveryFileURL != nil { cats.append(.recovery) }
        cats.append(contentsOf: [
            .sync,
            .weather,
            .notifications,
            .health,
            .appearance,
            .units,
            .export,
            .feedback,
        ])
        return cats
    }
    
    @ViewBuilder
    private func iPadDetailContent(for category: SettingsCategory) -> some View {
        // Every category renders inside a `Form` so the existing
        // `Section`-based section views look identical to the iPhone
        // version. Forms inside a NavigationSplitView detail column
        // pick up the standard grouped style automatically.
        Form {
            switch category {
            case .recovery:
                recoverySection
            case .sync:
                dataSyncSection
            case .weather:
                weatherTrackingSection
                backfillSection
            case .notifications:
                notificationsSection
            case .health:
                appleHealthSection
            case .appearance:
                appearanceSection
            case .units:
                unitsSection
            case .export:
                exportSection
            case .feedback:
                feedbackSection
            }
        }
    }
    
    // MARK: - Form Sections
    
    private var dataSyncSection: some View {
        Section(header: Text("Data Sync")) {
            Toggle("Enable iCloud Sync", isOn: $settings.useICloudSync)
                .onChange(of: settings.useICloudSync) { _, newValue in
                    if newValue {
                        showingMigrationAlert = true
                    }
                }
            
            Text("When enabled, your data will sync across all your devices using iCloud")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var weatherTrackingSection: some View {
        Section(header: Text("Weather Tracking")) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location Services")
                        .font(.body)
                    Text(locationStatusText)
                        .font(.caption)
                        .foregroundColor(locationStatusColor)
                }
                Spacer()
                Button(locationButtonText) {
                    handleLocationPermission()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(locationManager.authorizationStatus == .notDetermined || 
                         locationManager.authorizationStatus == .authorizedWhenInUse || 
                         locationManager.authorizationStatus == .authorizedAlways)
            }
            
            if locationManager.authorizationStatus == .notDetermined {
                iOS26LocationInfoView()
            }
            
            WeatherTrackingInfoView()
        }
    }
    
    private var backfillSection: some View {
        Section(header: Text("Backfill Weather Data")) {
            VStack(alignment: .leading, spacing: 12) {
                backfillHeaderView
                
                if locationManager.authorizationStatus == .notDetermined {
                    iOS26BackfillInfoView()
                } else {
                    Text("Fetches historical weather data for all migraine entries that don't have it. This uses your current location or the location where you logged the migraine.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var backfillHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Weather to Past Entries")
                    .font(.body)
                if isBackfilling {
                    Text("Processing \(backfillProgress) of \(backfillTotal)...")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    let count = viewModel.migraines.filter { !$0.hasWeatherData }.count
                    if count > 0 {
                        Text("\(count) entries without weather data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("All entries have weather data")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            Spacer()
            Button(action: {
                Task {
                    await performBackfill()
                }
            }) {
                if isBackfilling {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Start")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isBackfilling || 
                     viewModel.migraines.filter { !$0.hasWeatherData }.isEmpty ||
                     locationManager.authorizationStatus == .notDetermined)
        }
    }
    
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.colorScheme) {
                ForEach(SettingsManager.ColorSchemePreference.allCases, id: \.self) { scheme in
                    Text(scheme.rawValue).tag(scheme)
                }
            }
        }
    }
    
    private var unitsSection: some View {
        Section {
            Picker("Temperature", selection: $settings.temperatureUnit) {
                ForEach(SettingsManager.TemperatureUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            
            Picker("Pressure", selection: $settings.pressureUnit) {
                ForEach(SettingsManager.PressureUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
        } header: {
            Text("Units")
        } footer: {
            Text("Choose your preferred units for weather data display.")
        }
    }
    
    // MARK: - Notifications
    //
    // Two opt-in push categories:
    //
    //   • Forecast risk — fires when the next 24h of weather forecast
    //     contains an hour the prediction engine scores as high risk
    //     against the user's own historical patterns. Body is
    //     informational ("conditions ahead match your past migraines") —
    //     never asks "how are you feeling?" per product direction.
    //
    //   • Re-engagement — daily 7pm reminder if the user hasn't logged
    //     anything in 14+ days. Phrased as "anything to add?" — never as
    //     a wellness check.
    //
    // Both are off by default. Enabling either one prompts for system
    // notification authorization on first toggle; if the user later
    // denies in System Settings we surface a deep link.

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { notificationManager.forecastRiskEnabled },
                set: { newValue in handleNotificationToggle(setting: \.forecastRiskEnabled, newValue: newValue) }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Migraine Risk Forecasts")
                        Text("Heads-up when upcoming weather matches your patterns.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "cloud.bolt.fill")
                        .foregroundColor(.orange)
                }
            }
            .accessibilityHint("When on, you'll get a push 1–2 hours before any high-risk weather window we detect.")

            Toggle(isOn: Binding(
                get: { notificationManager.reengagementEnabled },
                set: { newValue in handleNotificationToggle(setting: \.reengagementEnabled, newValue: newValue) }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Catch-Up Reminders")
                        Text("Quiet nudge after \(notificationManager.reengagementDays) days without an entry.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.indigo)
                }
            }
            .accessibilityHint("When on, you'll be reminded once a day after a long gap so your trends stay accurate.")
        } header: {
            Text("Notifications")
        } footer: {
            Text("Notifications never ask how you're feeling — they just point out patterns or remind you to log migraines you might have missed. Allow notifications in iOS Settings if prompted.")
        }
        .alert("Notifications Disabled", isPresented: $showingNotificationDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Headway can't send notifications right now because you previously turned them off in iOS Settings. Open Settings to re-enable them.")
        }
    }

    /// Shared handler for the two notification toggles. Centralizes the
    /// "request auth on first enable, deep-link to Settings on denial"
    /// dance so the toggle bodies stay readable.
    private func handleNotificationToggle(
        setting keyPath: ReferenceWritableKeyPath<NotificationManager, Bool>,
        newValue: Bool
    ) {
        if newValue {
            // User is turning it ON — make sure we have OS-level auth
            // before flipping our own flag. If the user denies, we don't
            // want the toggle to land in a misleading "on" state.
            Task { @MainActor in
                await notificationManager.refreshAuthorizationStatus()
                if notificationManager.authorizationStatus == .denied {
                    showingNotificationDeniedAlert = true
                    return
                }
                if notificationManager.authorizationStatus == .notDetermined {
                    let granted = await notificationManager.requestAuthorization()
                    guard granted else {
                        // User denied at the system prompt; leave our
                        // toggle off and don't show a second alert (the
                        // OS already gave them feedback).
                        return
                    }
                }
                notificationManager[keyPath: keyPath] = true
                // Kick off an immediate reconcile so the user gets the
                // expected behavior without waiting for the next BG run.
                await notificationManager.reconcileAllNotifications(
                    migraines: viewModel.migraines,
                    forecast: WeatherForecastService.shared.next(hours: 24)
                )
            }
        } else {
            notificationManager[keyPath: keyPath] = false
        }
    }

    // MARK: - Apple Health
    //
    // Mirrors logged migraines into Apple Health as `.headache` category
    // samples (iOS 17+). Off by default — flipping the toggle requests
    // HealthKit auth on first enable, and a manual "Sync All Migraines Now"
    // button lets users backfill historical entries (idempotent thanks to
    // the ExternalUUID-keyed delete-then-write path inside
    // `HealthKitManager.writeMigraineToHealth`). The whole section is
    // hidden on devices that don't have HealthKit (iPad without Health,
    // simulators without Health framework, etc.) — there's nothing the
    // user can do there.

    @ViewBuilder
    private var appleHealthSection: some View {
        if healthKitManager.isAvailable {
            Section {
                Toggle(isOn: Binding(
                    get: { healthKitManager.isHealthSyncEnabled },
                    set: { newValue in
                        healthKitManager.isHealthSyncEnabled = newValue
                        if newValue {
                            // First-time enable: request HealthKit
                            // authorization. The system shows the standard
                            // sheet listing the categories we need (read
                            // sleep/HRV/etc + write headache); the user can
                            // approve any subset, and our writes silently
                            // no-op for the unapproved types. Detached so
                            // the toggle UI flips immediately rather than
                            // waiting on the auth sheet to be dismissed.
                            Task { @MainActor in
                                await healthKitManager.requestAuthorization()
                            }
                        }
                    }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mirror Migraines to Apple Health")
                            Text(healthKitManager.isHealthSyncEnabled
                                 ? "New entries are saved as Headache samples."
                                 : "Off — Apple Health does not receive your migraines.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundColor(.pink)
                    }
                }
                .accessibilityHint("When on, every migraine you save is also written to Apple Health as a Headache entry.")

                if healthKitManager.isHealthSyncEnabled {
                    Button {
                        Task { await performHealthBackfill() }
                    } label: {
                        HStack {
                            Label {
                                Text("Sync All Migraines Now")
                            } icon: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                            if isHealthBackfilling {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isHealthBackfilling || viewModel.migraines.isEmpty)
                    .accessibilityHint("Writes every migraine in your log to Apple Health, replacing any prior copies.")
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Mirroring uses Apple Health's Headache type so your entries appear under Browse → Symptoms → Headache and become available to other Health-aware apps you've authorized. Pain levels 1–3 record as Mild, 4–6 as Moderate, and 7–10 as Severe. You can revoke access anytime in Health → Sharing → Apps.")
            }
            .alert("Apple Health Sync", isPresented: $showingHealthBackfillAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(healthBackfillResult)
            }
        }
    }

    private func performHealthBackfill() async {
        isHealthBackfilling = true
        defer { isHealthBackfilling = false }

        // Make sure we're authorized before kicking off — otherwise every
        // per-migraine write would no-op silently and the user would just
        // see "Wrote 0 entries" with no explanation.
        await healthKitManager.requestAuthorization()

        guard healthKitManager.isAuthorized else {
            healthBackfillResult = "Apple Health did not authorize this app to write headache entries. You can change that in Health → Sharing → Apps → Headway."
            showingHealthBackfillAlert = true
            return
        }

        if #available(iOS 17.0, *) {
            let (written, failed) = await healthKitManager.backfillMigrainesToHealth(viewModel.migraines)
            if failed > 0 {
                healthBackfillResult = "Synced \(written) entries to Apple Health. \(failed) entries could not be synced (missing date or id)."
            } else {
                healthBackfillResult = "Synced \(written) \(written == 1 ? "entry" : "entries") to Apple Health."
            }
        } else {
            healthBackfillResult = "Apple Health migraine sync requires iOS 17 or later."
        }
        showingHealthBackfillAlert = true
    }

    private var exportSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                exportHeaderView
                
                Picker("Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                
                ExportPrivacyWarningView()
            }
        } header: {
            Text("Data Export")
        } footer: {
            Text("Export your migraine history to share with healthcare providers. PDF creates a formatted report; CSV works with Excel and Google Sheets.")
        }
    }
    
    // MARK: - Help & Feedback

    /// Always-available entry points for rating the app on the App Store
    /// (system review prompt is rate-limited and gated behind the
    /// "Enjoying Headway?" pre-prompt; this row gives the user an
    /// unconditional way to leave a review when they want to) and for
    /// sending in-app feedback (routes to the same `FeedbackFormView`
    /// the "Not really" path uses, but with `origin = .settings` so
    /// the copy is friendlier).
    private var feedbackSection: some View {
        Section {
            Link(destination: AppContactInfo.appStoreWriteReviewURL) {
                Label {
                    Text("Rate Headway on the App Store")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .accessibilityLabel("Rate Headway on the App Store")
            .accessibilityHint("Opens the App Store to the review page for Headway.")

            Button {
                showingFeedbackForm = true
            } label: {
                Label {
                    Text("Send Feedback")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.blue)
                }
            }
            .accessibilityLabel("Send feedback")
            .accessibilityHint("Opens an in-app form to send feedback, bug reports, or feature requests to the developer.")

            Link(destination: AppContactInfo.privacyPolicyURL) {
                Label {
                    Text("Privacy Policy")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                }
            }
            .accessibilityLabel("View privacy policy")
            .accessibilityHint("Opens the full Headway privacy policy in your default browser.")
        } header: {
            Text("Help & Feedback")
        } footer: {
            Text("Reviews help other migraine sufferers find Headway. Feedback goes directly to the developer — replies come from a real person, not an autoresponder.")
        }
    }

    private var exportHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Migraine Data")
                    .font(.body)
                Text("\(viewModel.migraines.count) entries available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isExporting {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("Export") {
                    showingExportWarning = true
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.migraines.isEmpty)
            }
        }
    }
    
    // MARK: - Recovery File

    /// Renders only when a moved-aside Core Data file is on disk *and* the
    /// path stored under `PersistenceController.lastRecoveryFileDefaultsKey`
    /// still resolves. Stale pointers are silently cleared on appear.
    @ViewBuilder
    private var recoverySection: some View {
        if let url = recoveryFileURL {
            Section {
                RecoveryFileBanner(
                    fileName: url.lastPathComponent,
                    modificationDate: recoveryFileModificationDate,
                    sizeBytes: recoveryFileSizeBytes
                )

                Button {
                    showingRecoveryShareSheet = true
                } label: {
                    Label("Share Recovered Database", systemImage: "square.and.arrow.up")
                }
                .accessibilityHint("Send the file to support, AirDrop, or save to Files for safekeeping.")

                Button(role: .destructive) {
                    showingRecoveryDismissConfirm = true
                } label: {
                    Label("Dismiss This Notice", systemImage: "xmark.circle")
                }
                .accessibilityHint("Hide this section. The backup file remains on disk.")
            } header: {
                Label("Database Recovered", systemImage: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
            } footer: {
                Text("On a recent app launch, the local database file could not be opened and was preserved as a backup. A fresh database has taken its place. Send the backup to support if you need help recovering older entries.")
            }
        }
    }

    /// Re-reads `UserDefaults` and disk so the section auto-hides if the
    /// user has already moved/deleted the file (e.g. via the share sheet
    /// → Save to Files → Move flow), or auto-appears if a fresh recovery
    /// happened while the app was backgrounded.
    private func refreshRecoveryFileMetadata() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: PersistenceController.lastRecoveryFileDefaultsKey) else {
            recoveryFileURL = nil
            recoveryFileModificationDate = nil
            recoveryFileSizeBytes = nil
            return
        }

        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            // Pointer is stale — file was moved or deleted out from under us.
            // Clear the key so we don't keep advertising a missing file.
            defaults.removeObject(forKey: PersistenceController.lastRecoveryFileDefaultsKey)
            recoveryFileURL = nil
            recoveryFileModificationDate = nil
            recoveryFileSizeBytes = nil
            return
        }

        recoveryFileURL = url
        if let attrs = try? fm.attributesOfItem(atPath: url.path) {
            recoveryFileModificationDate = attrs[.modificationDate] as? Date
            recoveryFileSizeBytes = (attrs[.size] as? NSNumber)?.int64Value
        } else {
            recoveryFileModificationDate = nil
            recoveryFileSizeBytes = nil
        }
    }

    /// Clears only the `UserDefaults` pointer; the file itself is left on
    /// disk so the user can still retrieve it via Files / iTunes file
    /// sharing if they change their mind. Logged so support can correlate.
    private func dismissRecoveryNotice() {
        UserDefaults.standard.removeObject(forKey: PersistenceController.lastRecoveryFileDefaultsKey)
        AppLogger.coreData.notice("Recovery notice dismissed by user; backup file left on disk.")
        recoveryFileURL = nil
        recoveryFileModificationDate = nil
        recoveryFileSizeBytes = nil
    }

    // MARK: - Backfill Helper
    
    private func performBackfill() async {
        await MainActor.run {
            isBackfilling = true
            backfillProgress = 0
            backfillTotal = 0
        }
        
        let result = await viewModel.backfillWeatherData { current, total in
            Task { @MainActor in
                self.backfillProgress = current
                self.backfillTotal = total
            }
        }
        
        await MainActor.run {
            isBackfilling = false
            
            if result.success > 0 || result.failed > 0 {
                backfillResult = "Successfully fetched weather data for \(result.success) entries. \(result.failed) failed."
            } else {
                backfillResult = "No entries needed weather data."
            }
            showingBackfillAlert = true
        }
    }
    
    // MARK: - Location Helpers
    
    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Enabled"
        case .denied, .restricted:
            return "Disabled"
        case .notDetermined:
            // In iOS 25+, this likely means "When I Share" is set
            return "When Shared"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var locationStatusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            // In iOS 25+, "When I Share" is acceptable for weather tracking
            return .blue
        @unknown default:
            return .gray
        }
    }
    
    private var locationButtonText: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Enabled"
        case .denied, .restricted:
            return "Open Settings"
        case .notDetermined:
            // In iOS 25+, .notDetermined means "When I Share" which is functional
            return "Enabled"
        @unknown default:
            return "Settings"
        }
    }
    
    private func handleLocationPermission() {
        let raw = locationManager.authorizationStatus.rawValue
        AppLogger.ui.debug("handleLocationPermission tapped; status raw=\(raw, privacy: .public)")

        switch locationManager.authorizationStatus {
        case .notDetermined:
            AppLogger.ui.debug("Location notDetermined → requesting permission")
            locationManager.requestPermission()
        case .denied, .restricted:
            AppLogger.ui.debug("Location denied/restricted → showing Open-Settings alert")
            showingLocationAlert = true
        case .authorizedWhenInUse, .authorizedAlways:
            AppLogger.ui.debug("Location already authorized; no action")
        @unknown default:
            AppLogger.ui.error("Unknown location authorization status raw=\(raw, privacy: .public)")
        }
    }
    
    private func performMigration() async {
        do {
            try await viewModel.migrateToDifferentStore()
        } catch {
            await MainActor.run {
                migrationErrorMessage = error.localizedDescription
                showingMigrationError = true
                settings.useICloudSync = false
            }
        }
    }
    
    // MARK: - Export Helpers
    
    private func performExport() async {
        await MainActor.run {
            isExporting = true
        }
        
        do {
            let url: URL
            switch exportFormat {
            case .csv:
                url = try await exportToCSV()
            case .pdf:
                url = try await exportToPDF()
            }
            
            await MainActor.run {
                isExporting = false
                exportURL = url
                showingExportSheet = true
            }
        } catch {
            await MainActor.run {
                isExporting = false
                exportErrorMessage = "Export failed: \(error.localizedDescription)"
                showingExportError = true
            }
        }
    }
    
    private func exportToCSV() async throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
        
        var csvContent = "Date,End Time,Pain Level,Location,Duration (hours),"
        csvContent += "Aura,Light Sensitivity,Sound Sensitivity,Nausea,Vomiting,Wake-up Headache,Tinnitus,Vertigo,"
        csvContent += "Stress,Lack of Sleep,Dehydration,Weather,Hormones,Alcohol,Caffeine,Food,Exercise,Screen Time,Other Trigger,"
        csvContent += "Ibuprofen,Excedrin,Tylenol,Sumatriptan,Rizatriptan,Naproxen,Frovatriptan,Naratriptan,Nurtec,Symbravo,Ubrelvy,Reyvow,Trudhesa,Elyxyb,Other Med,"
        csvContent += "Missed Work,Missed School,Missed Events,"
        csvContent += "Temperature (\(settings.temperatureUnit.symbol)),Pressure (\(settings.pressureUnit.symbol)),Pressure Change 24h (\(settings.pressureUnit.symbol)),Weather Condition,"
        csvContent += "Notes\n"
        
        for migraine in viewModel.migraines.sorted(by: { ($0.startTime ?? Date()) > ($1.startTime ?? Date()) }) {
            var row: [String] = []
            
            // Date and time
            row.append(migraine.startTime.map { dateFormatter.string(from: $0) } ?? "")
            row.append(migraine.endTime.map { dateFormatter.string(from: $0) } ?? "")
            row.append("\(migraine.painLevel)")
            row.append(escapeCSV(migraine.location ?? ""))
            
            // Duration
            if let start = migraine.startTime, let end = migraine.endTime {
                let hours = end.timeIntervalSince(start) / 3600
                row.append(String(format: "%.1f", hours))
            } else {
                row.append("")
            }
            
            // Symptoms
            row.append(migraine.hasAura ? "Yes" : "No")
            row.append(migraine.hasPhotophobia ? "Yes" : "No")
            row.append(migraine.hasPhonophobia ? "Yes" : "No")
            row.append(migraine.hasNausea ? "Yes" : "No")
            row.append(migraine.hasVomiting ? "Yes" : "No")
            row.append(migraine.hasWakeUpHeadache ? "Yes" : "No")
            row.append(migraine.hasTinnitus ? "Yes" : "No")
            row.append(migraine.hasVertigo ? "Yes" : "No")
            
            // Triggers — column order MUST match the CSV header above. Using
            // a fixed `csvTriggerOrder` so adding/removing a case in the enum
            // can't silently shift columns and break downstream parsers.
            for trigger in Self.csvTriggerOrder {
                row.append(migraine.triggers.contains(trigger) ? "Yes" : "No")
            }

            // Medications — column order MUST match the CSV header above.
            // Note: `MigraineMedication.eletriptan` is intentionally omitted to
            // preserve byte-for-byte compatibility with previously exported
            // CSVs. (Adding a new column would break existing user pipelines.)
            for medication in Self.csvMedicationOrder {
                row.append(migraine.medications.contains(medication) ? "Yes" : "No")
            }
            
            // Impact
            row.append(migraine.missedWork ? "Yes" : "No")
            row.append(migraine.missedSchool ? "Yes" : "No")
            row.append(migraine.missedEvents ? "Yes" : "No")
            
            // Weather
            if migraine.hasWeatherData {
                row.append(String(format: "%.1f", settings.convertTemperature(migraine.weatherTemperature)))
                row.append(String(format: "%.2f", settings.convertPressure(migraine.weatherPressure)))
                row.append(String(format: "%.2f", settings.convertPressure(migraine.weatherPressureChange24h)))
                row.append(WeatherService.weatherCondition(for: Int(migraine.weatherCode)))
            } else {
                row.append("")
                row.append("")
                row.append("")
                row.append("")
            }
            
            // Notes
            row.append(escapeCSV(migraine.notes ?? ""))
            
            csvContent += row.joined(separator: ",") + "\n"
        }
        
        let fileName = "Headway_Migraine_Export_\(fileDateFormatter.string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        return tempURL
    }
    
    private func exportToPDF() async throws -> URL {
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let sortedMigraines = viewModel.migraines.sorted { ($0.startTime ?? Date()) > ($1.startTime ?? Date()) }
        
        // Create PDF renderer
        let pageWidth: CGFloat = 612  // US Letter width in points
        let pageHeight: CGFloat = 792 // US Letter height in points
        let margin: CGFloat = 50
        let contentWidth = pageWidth - (margin * 2)
        
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        
        let data = pdfRenderer.pdfData { context in
            var currentY: CGFloat = margin
            var pageNumber = 1
            
            // Helper to start a new page
            func startNewPage() {
                context.beginPage()
                currentY = margin
                pageNumber += 1
            }
            
            // Helper to check if we need a new page
            func checkPageBreak(neededHeight: CGFloat) {
                if currentY + neededHeight > pageHeight - margin {
                    startNewPage()
                }
            }
            
            // Text styles
            let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
            let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 11)
            let captionFont = UIFont.systemFont(ofSize: 9)
            
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            
            let leftStyle = NSMutableParagraphStyle()
            leftStyle.alignment = .left
            
            // Start first page
            context.beginPage()
            
            // Title
            let title = "Migraine History Report"
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: titleStyle
            ]
            title.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 30), withAttributes: titleAttrs)
            currentY += 40
            
            // Privacy warning
            let warningAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: titleStyle
            ]
            let warning = "⚠️ CONFIDENTIAL HEALTH INFORMATION - Handle with care and delete after use"
            warning.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 20), withAttributes: warningAttrs)
            currentY += 30
            
            // Export info
            let infoAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor.gray,
                .paragraphStyle: titleStyle
            ]
            let exportInfo = "Generated: \(dateFormatter.string(from: Date())) • Total Entries: \(sortedMigraines.count)"
            exportInfo.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 15), withAttributes: infoAttrs)
            currentY += 30
            
            // Divider
            UIColor.lightGray.setStroke()
            let dividerPath = UIBezierPath()
            dividerPath.move(to: CGPoint(x: margin, y: currentY))
            dividerPath.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
            dividerPath.lineWidth = 0.5
            dividerPath.stroke()
            currentY += 20
            
            // Summary section
            let summaryHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: leftStyle
            ]
            "SUMMARY".draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 20), withAttributes: summaryHeaderAttrs)
            currentY += 25
            
            // Calculate summary stats
            let totalMigraines = sortedMigraines.count
            let migrainesWithPain = sortedMigraines.filter { $0.painLevel > 0 }
            let avgPain = migrainesWithPain.count > 0 ? Double(migrainesWithPain.reduce(0) { $0 + Int($1.painLevel) }) / Double(migrainesWithPain.count) : 0
            let withAura = sortedMigraines.filter { $0.hasAura }.count
            let missedWorkCount = sortedMigraines.filter { $0.missedWork }.count
            
            let summaryAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: leftStyle
            ]
            
            let summaryText = """
            • Total migraine episodes recorded: \(totalMigraines)
            • Average pain level: \(String(format: "%.1f", avgPain))/10
            • Episodes with aura: \(withAura) (\(totalMigraines > 0 ? Int(Double(withAura)/Double(totalMigraines)*100) : 0)%)
            • Missed work/school events: \(missedWorkCount)
            """
            summaryText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 80), withAttributes: summaryAttrs)
            currentY += 90
            
            // Divider
            UIColor.lightGray.setStroke()
            let divider2 = UIBezierPath()
            divider2.move(to: CGPoint(x: margin, y: currentY))
            divider2.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
            divider2.lineWidth = 0.5
            divider2.stroke()
            currentY += 20
            
            // Individual entries
            "DETAILED MIGRAINE LOG".draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 20), withAttributes: summaryHeaderAttrs)
            currentY += 30
            
            for (index, migraine) in sortedMigraines.enumerated() {
                // Estimate height needed for this entry
                let entryHeight: CGFloat = 140
                checkPageBreak(neededHeight: entryHeight)
                
                // Entry header with date and pain level
                let dateStr = migraine.startTime.map { dateFormatter.string(from: $0) } ?? "Unknown date"
                let entryHeader = "#\(index + 1) - \(dateStr)"
                let entryHeaderAttrs: [NSAttributedString.Key: Any] = [
                    .font: headerFont,
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: leftStyle
                ]
                entryHeader.draw(in: CGRect(x: margin, y: currentY, width: contentWidth - 80, height: 18), withAttributes: entryHeaderAttrs)
                
                // Pain level badge
                let painLevel = Int(migraine.painLevel)
                let painText = painLevel > 0 ? "Pain: \(painLevel)/10" : "Pain: N/A"
                let painColor: UIColor = painLevel >= 7 ? .systemRed : (painLevel >= 4 ? .systemOrange : .systemGreen)
                let rightAlignStyle = NSMutableParagraphStyle()
                rightAlignStyle.alignment = .right
                let painAttrs: [NSAttributedString.Key: Any] = [
                    .font: headerFont,
                    .foregroundColor: painColor,
                    .paragraphStyle: rightAlignStyle
                ]
                painText.draw(in: CGRect(x: pageWidth - margin - 100, y: currentY, width: 100, height: 18), withAttributes: painAttrs)
                currentY += 22
                
                // Location
                if let location = migraine.location, !location.isEmpty {
                    let locationText = "📍 \(location)"
                    locationText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 15), withAttributes: summaryAttrs)
                    currentY += 18
                }
                
                // Symptoms
                var symptoms: [String] = []
                if migraine.hasAura { symptoms.append("Aura") }
                if migraine.hasPhotophobia { symptoms.append("Light sensitivity") }
                if migraine.hasPhonophobia { symptoms.append("Sound sensitivity") }
                if migraine.hasNausea { symptoms.append("Nausea") }
                if migraine.hasVomiting { symptoms.append("Vomiting") }
                if migraine.hasVertigo { symptoms.append("Vertigo") }
                if migraine.hasTinnitus { symptoms.append("Tinnitus") }
                if migraine.hasWakeUpHeadache { symptoms.append("Wake-up headache") }
                
                if !symptoms.isEmpty {
                    let symptomsText = "Symptoms: \(symptoms.joined(separator: ", "))"
                    symptomsText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 30), withAttributes: summaryAttrs)
                    currentY += symptoms.count > 4 ? 35 : 20
                }
                
                let triggers = migraine.orderedTriggers.map(\.displayName)
                if !triggers.isEmpty {
                    let triggersText = "Triggers: \(triggers.joined(separator: ", "))"
                    triggersText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 30), withAttributes: summaryAttrs)
                    currentY += triggers.count > 4 ? 35 : 20
                }

                let meds = migraine.orderedMedications.map(\.displayName)
                if !meds.isEmpty {
                    let medsText = "Medications: \(meds.joined(separator: ", "))"
                    medsText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 30), withAttributes: summaryAttrs)
                    currentY += meds.count > 4 ? 35 : 20
                }
                
                // Weather data
                if migraine.hasWeatherData {
                    let temp = settings.convertTemperature(migraine.weatherTemperature)
                    let pressure = settings.convertPressure(migraine.weatherPressure)
                    let pressureChange = settings.convertPressure(migraine.weatherPressureChange24h)
                    let changeIndicator = pressureChange >= 0 ? "↑" : "↓"
                    let weatherText = "Weather: \(String(format: "%.0f", temp))\(settings.temperatureUnit.symbol), \(String(format: "%.1f", pressure)) \(settings.pressureUnit.symbol) (\(changeIndicator)\(String(format: "%.2f", abs(pressureChange))) \(settings.pressureUnit.symbol)/24h)"
                    weatherText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 15), withAttributes: summaryAttrs)
                    currentY += 20
                }
                
                // Notes
                if let notes = migraine.notes, !notes.isEmpty {
                    let notesText = "Notes: \(notes)"
                    let notesRect = CGRect(x: margin, y: currentY, width: contentWidth, height: 40)
                    notesText.draw(in: notesRect, withAttributes: summaryAttrs)
                    currentY += 45
                }
                
                // Entry divider
                currentY += 5
                UIColor(white: 0.9, alpha: 1).setStroke()
                let entryDivider = UIBezierPath()
                entryDivider.move(to: CGPoint(x: margin + 20, y: currentY))
                entryDivider.addLine(to: CGPoint(x: pageWidth - margin - 20, y: currentY))
                entryDivider.lineWidth = 0.3
                entryDivider.stroke()
                currentY += 15
            }
            
            // Footer on last page
            checkPageBreak(neededHeight: 50)
            currentY = pageHeight - margin - 30
            
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor.gray,
                .paragraphStyle: titleStyle
            ]
            let footer = "Generated by Headway Migraine Log • This document contains sensitive health information"
            footer.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 20), withAttributes: footerAttrs)
        }
        
        let fileName = "Headway_Migraine_Report_\(fileDateFormatter.string(from: Date())).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL)
        
        return tempURL
    }
    
    private func escapeCSV(_ string: String) -> String {
        var result = string
        // Replace newlines with spaces
        result = result.replacingOccurrences(of: "\n", with: " ")
        result = result.replacingOccurrences(of: "\r", with: " ")
        // If contains comma, quote, or special chars, wrap in quotes
        if result.contains(",") || result.contains("\"") || result.contains("\n") {
            result = result.replacingOccurrences(of: "\"", with: "\"\"")
            result = "\"\(result)\""
        }
        return result
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Helper Views

struct iOS26LocationInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text("Weather Tracking Enabled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text("iOS 26 uses 'When I Share' as the standard location permission. Weather tracking works perfectly - you'll see a quick permission prompt when saving new entries.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("How it works:")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                LocationStepRow(step: 1, text: "Save a new migraine entry")
                LocationStepRow(step: 2, text: "iOS asks 'Allow Headway to use your location?'")
                LocationStepRow(step: 3, text: "Tap 'Allow Once' - weather data is automatically fetched")
                LocationStepRow(step: 4, text: "Done! Repeat for each entry to track weather patterns")
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 12))
                    Text("Privacy First")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                Text("This is Apple's new privacy-first approach in iOS 26. You stay in control - approve location access only when you need it.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color(.systemGreen).opacity(0.1))
        .cornerRadius(8)
    }
}

struct LocationStepRow: View {
    let step: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "\(step).circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct WeatherTrackingInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cloud.sun.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))
                Text("How Weather Tracking Works")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text("Your location is used to fetch historical weather data (temperature, barometric pressure, precipitation) for each migraine entry. This helps identify weather-related triggers like pressure changes, which are a common migraine cause.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text("Your location data is only used to fetch weather and is never shared with third parties.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct iOS26BackfillInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))
                Text("Add Weather to Past Entries")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text("With iOS 26's privacy-first approach, you can add weather data to past entries one at a time. This gives you full control over which entries get weather data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("How to add weather to a past entry:")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                BackfillStepRow(step: "1", text: "Tap any past migraine entry to open details")
                BackfillStepRow(step: "2", text: "Scroll to Weather Data and tap 'Fetch Weather'")
                BackfillStepRow(step: "3", text: "When iOS asks, tap 'Allow Once'")
                BackfillStepRow(step: "4", text: "Weather data is added! Repeat for other entries")
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                        .font(.system(size: 12))
                    Text("Pro Tip")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                Text("Focus on entries where you remember severe symptoms or unusual circumstances. Weather correlation analysis works best with quality data from significant migraine events.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color(.systemBlue).opacity(0.1))
        .cornerRadius(8)
    }
}

struct BackfillStepRow: View {
    let step: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(step).")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// Read-only summary card for the moved-aside Core Data backup file.
/// Lives inside the recovery `Section`; the Share / Dismiss actions are
/// the surrounding `Button`s.
struct RecoveryFileBanner: View {
    let fileName: String
    let modificationDate: Date?
    let sizeBytes: Int64?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f
    }()

    private var formattedSize: String? {
        guard let sizeBytes else { return nil }
        return Self.byteCountFormatter.string(fromByteCount: sizeBytes)
    }

    private var formattedDate: String? {
        guard let modificationDate else { return nil }
        return Self.dateFormatter.string(from: modificationDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text("Backup Available")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Text(fileName)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .accessibilityLabel("File name: \(fileName)")

            HStack(spacing: 12) {
                if let formattedDate {
                    Label(formattedDate, systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Recovered \(formattedDate)")
                }
                if let formattedSize {
                    Label(formattedSize, systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Size \(formattedSize)")
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct ExportPrivacyWarningView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text("Privacy Notice")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text("Exported data will be unencrypted and may contain sensitive health information including migraine dates, symptoms, medications, and location data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.systemOrange).opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return SettingsView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
} 