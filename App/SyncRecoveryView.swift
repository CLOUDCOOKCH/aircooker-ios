import MealfCore
import SwiftUI

struct SyncRecoveryView: View {
  @Environment(AppModel.self) private var model
  @State private var confirmRebuild = false
  var body: some View {
    List {
      if model.resyncRequired || model.resyncRebuilding {
        Section("server_recovery") {
          Text("server_history_recovery_explanation").foregroundStyle(.secondary)
          Text("recovery_cached_records \(model.cachedRecordCount)")
          Text("pending_changes \(model.pending)")
          if model.resyncRebuilding {
            Text("recovery_staged_records \(model.resyncStagedCount)").font(.caption)
          }
          Button {
            if model.resyncRebuilding {
              Task { await model.rebuildFromServer() }
            } else {
              confirmRebuild = true
            }
          } label: {
            if model.resyncRebuilding {
              Text("resume_server_recovery")
            } else {
              Text("rebuild_from_server")
            }
          }.disabled(model.busy)
          if model.busy { ProgressView("recovery_working") }
        }
      }
      if model.authenticationExpired {
        Section {
          Text("recovery_sign_in_hint").foregroundStyle(.secondary)
          Button("sign_in_again") { model.beginPasswordUnlock() }.disabled(model.busy)
        }
      }
      Section {
        Text("sync_recovery_explanation").foregroundStyle(.secondary)
        Button("sync_now") { Task { await model.synchronise() } }.disabled(model.busy)
      }
      Section("sync_needs_review") {
        if model.syncIssues.isEmpty {
          Text("sync_no_issues").foregroundStyle(.secondary)
        }
        ForEach(model.syncIssues) { issue in
          NavigationLink {
            SyncIssueView(issue: issue)
          } label: {
            VStack(alignment: .leading) {
              Text(recoveryTitle(issue.local.payload, kind: issue.kind))
              Text(recoveryReason(issue.code)).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      Section {
        NavigationLink("saved_local_drafts") { ArchivedDraftsView() }
      } footer: {
        Text("sync_archives_local_only")
      }
    }
    .navigationTitle("sync_recovery")
    .task { await model.reload() }
    .confirmationDialog(
      "confirm_server_recovery", isPresented: $confirmRebuild, titleVisibility: .visible
    ) {
      Button("rebuild_from_server") { Task { await model.rebuildFromServer() } }
      Button("cancel", role: .cancel) {}
    } message: {
      Text("server_history_recovery_explanation")
    }
  }
}

private struct SyncIssueView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let issue: SyncIssue
  @State private var choice: RecoveryChoice?
  var body: some View {
    Form {
      Section("local_version") {
        Text(recoveryTitle(issue.local.payload, kind: issue.kind)).font(.headline)
        Text(recoveryReason(issue.code)).foregroundStyle(.secondary)
        Text("pending_changes \(issue.mutationCount)").font(.caption)
        RecoveryPayload(
          payload: issue.local.payload, kind: issue.kind, deleted: issue.local.deleted)
      }
      Section("server_version") {
        if let server = issue.server {
          RecoveryPayload(payload: server.payload, kind: server.kind, deleted: server.deleted)
        } else {
          Text("sync_server_version_unavailable").foregroundStyle(.secondary)
        }
      }
      Section {
        if issue.kind == .recipe && !issue.local.deleted {
          Button("keep_new_recipe_copy") { choice = .copy }
        }
        Button("use_server_keep_draft") { choice = .server }
        if issue.code != "rejected_tombstone" {
          Button("retry_same_change") {
            Task { if await model.retrySyncIssue(issue) { dismiss() } }
          }
        }
      } footer: {
        Text("sync_recovery_archive_hint")
      }
      OperationErrorNotice()
    }
    .navigationTitle("sync_review_change")
    .disabled(model.busy || model.resyncRequired)
    .confirmationDialog(
      "sync_confirm_recovery",
      isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } }),
      titleVisibility: .visible
    ) {
      if choice == .copy {
        Button("keep_new_recipe_copy") {
          choice = nil
          Task { if await model.resolveSyncIssue(issue, keepRecipeCopy: true) { dismiss() } }
        }
      } else {
        Button("use_server_keep_draft") {
          choice = nil
          Task { if await model.resolveSyncIssue(issue, keepRecipeCopy: false) { dismiss() } }
        }
      }
      Button("cancel", role: .cancel) { choice = nil }
    } message: {
      Text("sync_recovery_archive_hint")
    }
  }
  private enum RecoveryChoice { case copy, server }
}

private struct RecoveryPayload: View {
  let payload: JSONValue
  let kind: EntityKind
  let deleted: Bool
  var body: some View {
    if deleted {
      Label("sync_record_deleted", systemImage: "trash")
    } else if kind == .recipe,
      let recipe = try? JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(payload))
    {
      Text(recipe.title).font(.headline)
      if !recipe.description.isEmpty { Text(recipe.description) }
      ForEach(recipe.ingredients) { ingredient in
        Text(
          [ingredient.quantity ?? "", ingredient.unit, ingredient.name, ingredient.preparation]
            .filter { !$0.isEmpty }.joined(separator: " "))
      }
      ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
        Text("\(index + 1). \(step)")
      }
      if !recipe.notes.isEmpty { Text(recipe.notes).foregroundStyle(.secondary) }
    } else {
      Text(recoveryJSON(payload)).font(.caption.monospaced()).textSelection(.enabled)
    }
  }
}

private struct ArchivedDraftsView: View {
  @Environment(AppModel.self) private var model
  @State private var drafts: [ArchivedDraft] = []
  @State private var more = true
  @State private var loading = false
  var body: some View {
    List {
      Section {
        Text("sync_archives_local_only").foregroundStyle(.secondary)
      }
      ForEach(drafts) { draft in
        NavigationLink {
          ArchivedDraftView(draft: draft)
        } label: {
          VStack(alignment: .leading) {
            Text(recoveryTitle(draft.payload, kind: draft.kind))
            if let date = ISO8601DateFormatter().date(from: draft.archivedAt) {
              Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      if more {
        Button("load_more") { Task { await load() } }.disabled(loading)
      }
      if drafts.isEmpty && !more { Text("no_saved_local_drafts") }
    }
    .navigationTitle("saved_local_drafts")
    .task { if drafts.isEmpty { await load() } }
  }
  private func load() async {
    guard !loading, let store = model.store else { return }
    loading = true
    defer { loading = false }
    do {
      let page = try await store.archivedDrafts(offset: drafts.count)
      drafts.append(contentsOf: page)
      more = page.count == 50
    } catch { model.report(error) }
  }
}

private struct ArchivedDraftView: View {
  @Environment(AppModel.self) private var model
  let draft: ArchivedDraft
  @State private var confirmCopy = false
  @State private var copied = false
  var body: some View {
    Form {
      Section { RecoveryPayload(payload: draft.payload, kind: draft.kind, deleted: draft.deleted) }
      Section {
        if draft.kind == .recipe && !draft.deleted {
          Button("keep_new_recipe_copy") { confirmCopy = true }.disabled(
            model.busy || model.resyncRequired || copied)
          if copied { Label("saved", systemImage: "checkmark") }
        }
        if let json = try? draft.exportJSON() { ShareLink("export_saved_draft", item: json) }
      } footer: {
        Text("saved_draft_export_hint")
      }
      OperationErrorNotice()
    }
    .navigationTitle("saved_local_draft")
    .confirmationDialog("keep_new_recipe_copy", isPresented: $confirmCopy) {
      Button("keep_new_recipe_copy") { Task { copied = await model.restoreArchivedRecipe(draft) } }
      Button("cancel", role: .cancel) {}
    }
  }
}

private func recoveryJSON(_ payload: JSONValue) -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  return (try? encoder.encode(payload)).map { String(decoding: $0, as: UTF8.self) } ?? ""
}
private func recoveryTitle(_ payload: JSONValue, kind: EntityKind) -> String {
  if case .object(let fields) = payload,
    let name = fields["title"]?.string ?? fields["name"]?.string, !name.isEmpty
  {
    return name
  }
  switch kind {
  case .recipe: return String(localized: "recipe")
  case .meal: return String(localized: "calendar")
  case .pantry: return String(localized: "pantry")
  case .leftover: return String(localized: "leftovers")
  case .template: return String(localized: "weekly_templates")
  }
}
private func recoveryReason(_ code: String) -> String {
  switch code {
  case "rejected_tombstone": return String(localized: "tombstone_conflict")
  case "insufficient_leftover_portions": return String(localized: "leftover_reserved_error")
  case "leftover_in_use", "leftover_recipe_in_use":
    return String(localized: "leftover_in_use_error")
  default: return String(localized: "sync_change_rejected") + " · " + code
  }
}
