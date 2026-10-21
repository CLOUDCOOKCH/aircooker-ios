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
          if !model.syncIssues.isEmpty { Text("sync_attention_hint").font(.caption) }
          HStack {
            Text("pending_changes \(model.pending)").font(.caption)
            Spacer()
            Button("retry") { Task { await model.synchronise() } }.disabled(model.busy)
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
          Text("welcome_title").font(.system(.largeTitle, design: .serif).weight(.semibold))
            .padding(.vertical, 8)
          Text("welcome_body").foregroundStyle(.secondary)
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
  private var today: [MealOccurrence] {
    (try? MealPlanning.expand(
      model.meals, from: model.dateString(Date()), through: model.dateString(Date()))) ?? []
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 30) {
        Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
          .font(.subheadline).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Text("today_meals").font(.title2.weight(.semibold))
            Spacer()
            NavigationLink {
              CalendarView(initialDate: model.dateString(Date()))
            } label: {
              Image(systemName: "arrow.up.right").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel(Text("calendar"))
          }
          if today.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
              Text("nothing_planned").font(.system(.title2, design: .serif))
              Text("plan_from_calendar").foregroundStyle(.secondary)
              NavigationLink("plan_meal") { CalendarView(initialDate: model.dateString(Date())) }
                .buttonStyle(.borderedProminent)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
              .background(
                KitchenStyle.surface, in: RoundedRectangle(cornerRadius: KitchenStyle.radius))
          }
          ForEach(today) { item in
            NavigationLink {
              RecipeDetail(id: item.meal.recipeID)
            } label: {
              MealRow(item: item)
            }
            .buttonStyle(.plain)
          }
        }
        VStack(alignment: .leading, spacing: 16) {
          Text("plan_your_week").font(.title2.weight(.semibold))
          if let week = try? PlanningDate.monday(containing: model.dateString(Date())) {
            NavigationLink {
              SuggestionsView(week: week)
            } label: {
              Label("weekly_suggestions", systemImage: "sparkles").frame(
                maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.bordered).controlSize(.large)
          }
          NavigationLink {
            LeftoversView()
          } label: {
            Label("leftovers", systemImage: "takeoutbag.and.cup.and.straw")
          }.frame(minHeight: 44)
        }
        VStack(alignment: .leading, spacing: 16) {
          Text("from_your_recipes").font(.title2.weight(.semibold))
          if model.recipes.isEmpty { Text("recipe_library_empty_hint").foregroundStyle(.secondary) }
          ForEach(Array(model.recipes.prefix(3))) { row in
            if let recipe = try? row.decode(Recipe.self) {
              NavigationLink {
                RecipeDetail(id: row.id)
              } label: {
                HStack(spacing: 14) {
                  RecipePhotoView(imageID: recipe.imageID).frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                  VStack(alignment: .leading, spacing: 5) {
                    Text(recipe.title).font(.headline).foregroundStyle(.primary)
                    Text("ingredient_count \(recipe.ingredients.count)").font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer(minLength: 0)
                }.frame(minHeight: 64)
              }.buttonStyle(.plain)
            }
          }
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { recipeActions }
            VStack(alignment: .leading, spacing: 12) { recipeActions }
          }.controlSize(.large)
        }
      }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
    }.background(KitchenStyle.background).navigationTitle("home_greeting")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NavigationLink {
            ImportView()
          } label: {
            Label("import_recipe", systemImage: "square.and.arrow.down")
          }
          Button("create_recipe", systemImage: "plus") { newRecipe = true }
        }
      }
      .refreshable { await model.synchronise() }
      .sheet(isPresented: $newRecipe) { RecipeEditor() }
  }
  @ViewBuilder private var recipeActions: some View {
    NavigationLink {
      ImportView()
    } label: {
      Label("import_recipe", systemImage: "square.and.arrow.down")
    }
    .buttonStyle(.borderedProminent)
    Button("create_recipe", systemImage: "plus") { newRecipe = true }.buttonStyle(.bordered)
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
        NavigationLink("sync_recovery") { SyncRecoveryView() }
      }
      if model.pendingSignOuts > 0 { SignOutStatusView() }
      Section("integrations") { Text("integration_console_hint").foregroundStyle(.secondary) }
      Section {
        Button("logout", role: .destructive) { Task { await model.logout() } }
          .disabled(model.signingOut)
        if model.signingOut { ProgressView("signing_out") }
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
