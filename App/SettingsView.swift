import AirCookerCore
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @AppStorage("startScreen") private var startScreen = "home"
  @AppStorage("biometricLock") private var biometricLock = false
  var body: some View {
    Form {
      Section("preferences") {
        Picker(selection: $startScreen) {
          Text("home").tag("home")
          Text("calendar").tag("calendar")
          Text("recipes").tag("recipes")
        } label: {
          Label("start_screen", systemImage: "house")
        }
        NavigationLink {
          ReminderSettingsView()
        } label: {
          Label("reminders_widgets", systemImage: "bell")
        }
        Toggle(
          isOn: Binding(
            get: { biometricLock },
            set: { value in
              if !value {
                biometricLock = false
              } else {
                Task { biometricLock = await model.enableLocalLock() }
              }
            })
        ) { Label("biometric_lock", systemImage: "faceid") }
      }.disabled(model.isDemo)
      if model.isDemo {
        Section("offline_demo") {
          Text("demo_intro")
          Text("demo_server_features").foregroundStyle(.secondary)
          Button("exit_demo") { Task { await model.endDemo() } }.disabled(model.busy)
        }
      } else {
        Section("sync_status") {
          LabeledContent {
            Text(model.pending, format: .number).monospacedDigit()
          } label: {
            Label("pending", systemImage: "arrow.triangle.2.circlepath")
          }
          NavigationLink {
            SyncRecoveryView()
          } label: {
            Label("sync_recovery", systemImage: "tray.full")
          }
          Button {
            Task { await model.synchronise() }
          } label: {
            Label("sync_now", systemImage: "arrow.clockwise")
          }.disabled(model.busy)
        }
        Section("server_connection") {
          NavigationLink {
            ServerConnectionView()
          } label: {
            Label("server_connection", systemImage: "server.rack")
          }
        }
        Section {
          Button("logout", role: .destructive) { Task { await model.logout() } }
            .disabled(model.signingOut)
          if model.signingOut { ProgressView("signing_out") }
        } footer: {
          Text("logout_keeps_local_data")
        }
      }
      if model.pendingSignOuts > 0 { SignOutStatusView() }
    }.navigationTitle("settings")
  }
}

private struct ServerConnectionView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    Form {
      Section("server_connection") {
        Text(model.server).font(.body).textSelection(.enabled)
      }
      Section("integrations") {
        Text("integration_console_hint").foregroundStyle(.secondary)
        if let url = URL(string: model.server), url.scheme == "https", url.host != nil,
          url.user == nil,
          url.password == nil
        {
          Link(destination: url) {
            Label("open_admin_console", systemImage: "arrow.up.right.square")
          }
        }
      }
    }.navigationTitle("server_connection").navigationBarTitleDisplayMode(.inline)
  }
}
