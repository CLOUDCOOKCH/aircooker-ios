import AirCookerCore
import SwiftUI

struct ImportView: View {
  @Environment(AppModel.self) private var model
  @State private var url = ""
  @State private var text = ""
  @State private var drafts: [ImportDraft] = []
  @State private var preview: ImportDraft?
  var body: some View {
    Form {
      Section("import_recipe") {
        TextField("import_url", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("import_text", text: $text, axis: .vertical).lineLimit(3...8)
        Button("import_start") {
          Task {
            await model.queueImport(url: url.isEmpty ? nil : url, text: text.isEmpty ? nil : text)
            url = ""
            text = ""
          }
        }.disabled(url.isEmpty && text.isEmpty)
      }
      Section {
        Text("import_pending").font(.footnote).foregroundStyle(.secondary)
        ForEach(drafts) { draft in
          if draft.state == "preview", draft.recipe != nil {
            Button(draft.recipe?.title ?? String(localized: "import_review")) { preview = draft }
          } else if draft.state == "needs_input" {
            VStack(alignment: .leading) {
              Text("import_failed")
              if let code = draft.errorCode {
                Text(code).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
              }
            }
          } else {
            Label(
              LocalizedStringKey(draft.state == "confirmed" ? "save" : "import_pending"),
              systemImage: draft.state == "confirmed" ? "checkmark.circle" : "clock")
          }
        }
      }
    }.navigationTitle("import_recipe")
      .sheet(item: $preview) { draft in
        if var recipe = draft.recipe {
          let _ = {
            recipe.provenance["import_job_id"] = draft.id.uuidString.lowercased()
            recipe.provenance["reviewed_by_user"] = "true"
          }()
          VStack {
            Text("import_uncertainty").font(.footnote).padding().background(.yellow.opacity(0.15))
            RecipeEditor(initial: recipe)
          }
        }
      }
      .task {
        while !Task.isCancelled {
          if let client = model.client {
            var values: [ImportDraft] = []
            for id in model.importIDs {
              if let draft = try? await client.importDraft(id: id) { values.append(draft) }
            }
            drafts = values
          }
          do { try await Task.sleep(for: .seconds(2)) } catch { break }
        }
      }
  }
}
