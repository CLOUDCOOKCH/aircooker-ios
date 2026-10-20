import AirCookerCore
import SwiftUI
import VisionKit

struct RootView: View {
  @Environment(AppModel.self) private var model
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
        }.onAppear { selection = startScreen }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if let error = model.error {
        VStack(alignment: .leading, spacing: 8) {
          Label(error, systemImage: "exclamationmark.icloud").font(.footnote)
          HStack {
            Text("pending_changes \(model.pending)").font(.caption)
            Spacer()
            Button("retry") { Task { await model.synchronise() } }
          }
        }.padding().background(.regularMaterial)
      } else if model.pending > 0 || model.busy {
        Label("pending_changes \(model.pending)", systemImage: "arrow.triangle.2.circlepath").font(
          .caption
        ).padding(8).frame(maxWidth: .infinity).background(.thinMaterial)
      }
    }
    .sheet(
      item: Binding(
        get: { model.connected && !model.locked ? model.destination : nil },
        set: { value in if model.connected && !model.locked { model.destination = value } }
      )
    ) { DestinationView(destination: $0) }
    .tint(Color(red: 0.21, green: 0.39, blue: 0.27))
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
          Image(systemName: "fork.knife.circle.fill").font(.system(size: 72)).foregroundStyle(
            .green
          ).accessibilityHidden(true)
          Text("welcome_title").font(.largeTitle.bold())
          Text("welcome_body").foregroundStyle(.secondary)
        }
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
            model.busy || server.isEmpty || username.isEmpty || password.isEmpty)
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
struct HomeView: View {
  @Environment(AppModel.self) private var model
  @State private var newRecipe = false
  var body: some View {
    List {
      Section {
        Text("home_greeting").font(.largeTitle.bold()).listRowSeparator(.hidden)
        Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide)).foregroundStyle(
          .secondary)
      }
      Section("today_meals") {
        let today =
          (try? MealPlanning.expand(
            model.meals, from: model.dateString(Date()),
            through: model.dateString(Date()))) ?? []
        if today.isEmpty {
          ContentUnavailableView(
            "nothing_planned", systemImage: "calendar.badge.plus",
            description: Text("plan_from_calendar"))
        }
        ForEach(today) { item in
          NavigationLink {
            RecipeDetail(id: item.meal.recipeID)
          } label: {
            Label(
              model.title(item.meal),
              systemImage: item.meal.category == "breakfast" ? "sunrise" : "fork.knife")
          }
        }
      }
      Section {
        if let week = try? PlanningDate.monday(containing: model.dateString(Date())) {
          NavigationLink("weekly_suggestions") { SuggestionsView(week: week) }
        }
        NavigationLink("leftovers") { LeftoversView() }
      }
      Section("your_kitchen") {
        LabeledContent("recipes", value: String(model.recipes.count))
        LabeledContent("pending", value: String(model.pending))
        LabeledContent("bring_status", value: String(localized: "not_configured"))
        Button("create_recipe", systemImage: "plus") { newRecipe = true }
        NavigationLink("import_recipe") { ImportView() }
      }
    }.navigationTitle("home").refreshable { await model.synchronise() }
      .sheet(isPresented: $newRecipe) { RecipeEditor() }
  }
}
struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @AppStorage("startScreen") private var startScreen = "home"
  @AppStorage("biometricLock") private var biometricLock = false
  var body: some View {
    Form {
      Section("preferences") {
        Picker("start_screen", selection: $startScreen) {
          Text("home").tag("home")
          Text("calendar").tag("calendar")
          Text("recipes").tag("recipes")
        }
        Toggle(
          "biometric_lock",
          isOn: Binding(
            get: { biometricLock },
            set: { value in
              if !value {
                biometricLock = false
              } else {
                Task { biometricLock = await model.enableLocalLock() }
              }
            }))
      }
      Section { NavigationLink("reminders_widgets") { ReminderSettingsView() } }
      Section("server_connection") {
        Text(model.server).font(.footnote).textSelection(.enabled)
        Button("sync_now") { Task { await model.synchronise() } }
        Text("pending_changes \(model.pending)")
      }
      Section("integrations") { Text("integration_console_hint").foregroundStyle(.secondary) }
      Section {
        Button("logout", role: .destructive) { Task { await model.logout() } }
        Text("logout_keeps_local_data").font(.footnote).foregroundStyle(.secondary)
      }
    }.navigationTitle("settings")
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
