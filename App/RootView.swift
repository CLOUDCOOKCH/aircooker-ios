import AirCookerCore
import SwiftUI
import VisionKit

struct RootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("startScreen") private var startScreen = "home"
  @State private var selection = "home"
  var body: some View {
    Group {
      if model.locked {
        ContentUnavailableView {
          Label("app_locked", systemImage: "lock.shield")
        } actions: {
          Button("unlock") { Task { await model.unlock() } }.buttonStyle(.borderedProminent)
          Button("use_password") { model.beginPasswordUnlock() }
        }
      } else if !model.connected {
        OnboardingView()
      } else {
        TabView(selection: $selection) {
          Tab("home", systemImage: "house", value: "home") { NavigationStack { HomeView() } }
          Tab("calendar", systemImage: "calendar", value: "calendar") {
            NavigationStack { CalendarView() }
          }
          Tab("recipes", systemImage: "book.closed", value: "recipes") {
            NavigationStack { RecipesView() }
          }
          Tab("pantry", systemImage: "cabinet", value: "pantry") {
            NavigationStack { PantryView() }
          }
          Tab("settings", systemImage: "gearshape", value: "settings") {
            NavigationStack { SettingsView() }
          }
        }.tabBarMinimizeBehavior(
          typeSize.isAccessibilitySize || reduceMotion ? .never : .onScrollDown
        ).onAppear { selection = startScreen }
      }
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        if model.isDemo {
          HStack(spacing: 12) {
            Label("offline_demo", systemImage: "eye").font(.caption)
            Spacer(minLength: 0)
            Button("exit_demo") { Task { await model.endDemo() } }
              .font(.caption).frame(minHeight: 44).disabled(model.busy)
              .accessibilityIdentifier("demo.exit")
          }.padding(.horizontal, 16).kitchenGlass(in: Capsule())
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        if let error = model.error {
          VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.icloud").font(.footnote)
            if !model.syncIssues.isEmpty { Text("sync_attention_hint").font(.caption) }
            HStack {
              if model.isDemo {
                Button("done") { model.error = nil }
              } else {
                Text("pending_changes \(model.pending)").font(.caption)
                Spacer()
                Button("retry") {
                  Task {
                    if model.ready { await model.synchronise() } else { await model.start() }
                  }
                }.disabled(model.busy)
              }
            }
          }.padding(16).kitchenGlass(in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 16).padding(.bottom, 8)
        } else if !model.isDemo && (model.pending > 0 || model.busy) {
          Label("pending_changes \(model.pending)", systemImage: "arrow.triangle.2.circlepath")
            .font(
              .caption
            ).padding(.horizontal, 16).padding(.vertical, 12)
            .kitchenGlass(in: Capsule()).padding(.horizontal, 16).padding(.bottom, 8)
        }
      }
    }
    .sheet(
      item: Binding(
        get: { model.connected && !model.locked ? model.destination : nil },
        set: { value in if model.connected && !model.locked { model.destination = value } }
      )
    ) { DestinationView(destination: $0) }
    .tint(KitchenStyle.accent)
  }
}
struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @State private var server = ""
  @State private var username = ""
  @State private var password = ""
  @State private var scanning = false
  @State private var firstRun = false
  @State private var setupToken = ""
  @State private var householdName = ""
  @State private var timezone = TimeZone.current.identifier
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("welcome_title").font(.largeTitle.weight(.semibold))
            .padding(.vertical, 8)
          Text("welcome_body").foregroundStyle(.secondary)
        }
        Section {
          Button("explore_demo", systemImage: "play.circle") { Task { await model.beginDemo() } }
            .disabled(!model.ready || model.busy).accessibilityIdentifier("onboarding.demo")
        } footer: {
          Text("demo_intro")
        }
        if model.pendingSignOuts > 0 { SignOutStatusView() }
        Section("server_connection") {
          TextField("server_url", text: $server).accessibilityIdentifier("onboarding.server")
            .keyboardType(.URL).textInputAutocapitalization(
              .never
            ).autocorrectionDisabled()
          if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            Button("scan_qr", systemImage: "qrcode.viewfinder") { scanning = true }
          }
          Toggle("first_run_setup", isOn: $firstRun)
          if firstRun {
            SecureField("setup_token", text: $setupToken)
            TextField("household_name", text: $householdName)
            TextField("household_timezone", text: $timezone).textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
          TextField("username", text: $username).textContentType(.username)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
          SecureField("password", text: $password).accessibilityIdentifier("onboarding.password")
            .textContentType(.password)
        }
        Section {
          Button("connect") {
            model.server = server.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
              if firstRun {
                await model.setup(
                  username: username, password: password, token: setupToken, name: householdName,
                  timezone: timezone)
              } else {
                await model.login(username: username, password: password)
              }
              password = ""
              setupToken = ""
            }
          }.accessibilityIdentifier("onboarding.connect").disabled(
            !model.ready || model.busy || server.isEmpty || username.isEmpty || password.isEmpty)
        } footer: {
          Text("setup_console_hint")
        }
      }.navigationTitle("aircooker").onAppear { server = model.server }
        .sheet(isPresented: $scanning) {
          QRScanner { value in
            server = value
            scanning = false
          }
        }
    }
  }
}
// Keep errors visible when an editing sheet covers the root sync status bar.
struct OperationErrorNotice: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    if let error = model.error {
      Label(error, systemImage: "exclamationmark.triangle")
        .font(.footnote).foregroundStyle(.red).padding()
        .frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
        .accessibilityAddTraits(.updatesFrequently)
    }
  }
}

/// Remains visible on onboarding after local logout and on settings after a new login.
struct SignOutStatusView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    Section("signout_pending_title") {
      Text("signout_pending_hint").foregroundStyle(.secondary)
      if model.retryingSignOuts {
        ProgressView("signout_retrying")
      } else {
        Button("signout_retry") { Task { await model.retrySignOuts() } }
      }
    }
  }
}
