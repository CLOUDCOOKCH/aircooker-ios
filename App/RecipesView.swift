import AirCookerCore
import PhotosUI
import SwiftUI

struct RecipesView: View {
  @Environment(AppModel.self) private var model
  @State private var search = ""
  @State private var creating = false
  var filtered: [LocalEntity] {
    model.recipes.filter {
      search.isEmpty
        || ((try? $0.decode(Recipe.self).title.localizedCaseInsensitiveContains(search)) ?? false)
    }
  }
  var body: some View {
    ScrollView {
      if model.recipes.isEmpty {
        ContentUnavailableView {
          Label("recipe_library_empty", systemImage: "book.closed")
        } description: {
          Text("recipe_library_empty_hint")
        } actions: {
          Button("create_recipe") { creating = true }.buttonStyle(.borderedProminent)
          NavigationLink("import_recipe") { ImportView() }.buttonStyle(.bordered)
        }.padding(.top, 32)
      } else if filtered.isEmpty {
        ContentUnavailableView.search(text: search).padding(.top, 32)
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 250), alignment: .top)], alignment: .leading,
          spacing: 20
        ) {
          ForEach(filtered) { row in
            if let recipe = try? row.decode(Recipe.self) {
              NavigationLink {
                RecipeDetail(id: row.id)
              } label: {
                RecipeCard(recipe: recipe)
              }
              .buttonStyle(.plain)
            }
          }
        }.padding(20)
      }
    }.background(KitchenStyle.background)
      .searchable(text: $search).navigationTitle("recipes")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NavigationLink {
            ImportView()
          } label: {
            Label("import_recipe", systemImage: "square.and.arrow.down")
          }
          Button("create_recipe", systemImage: "plus") { creating = true }
        }
      }
      .sheet(isPresented: $creating) { RecipeEditor() }
      .refreshable { await model.synchronise() }
  }
}
struct RecipeDetail: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let id: UUID
  @State private var editing = false
  @State private var servingCount = 2
  @State private var deleting = false
  var body: some View {
    if let recipe = model.recipe(id) {
      List {
        if recipe.imageID != nil {
          RecipePhotoView(imageID: recipe.imageID).frame(height: 220)
            .listRowInsets(EdgeInsets()).accessibilityLabel(Text("recipe_photo"))
        }
        Section {
          Text(recipe.title).font(.largeTitle.weight(.semibold))
          if !recipe.description.isEmpty { Text(recipe.description) }
        }
        Section("ingredients") {
          Stepper("servings_count \(servingCount)", value: $servingCount, in: 1...100)
          let ratio = Decimal(servingCount) / (Decimal(string: recipe.servings) ?? 2)
          ForEach(recipe.ingredients) { item in
            let ingredient = item.scaled(by: ratio)
            VStack(alignment: .leading) {
              Text(
                [
                  ingredient.quantity, ingredient.quantityMax.map { "–" + $0 }, ingredient.unit,
                  ingredient.name,
                ].compactMap { $0 }.joined(separator: " "))
              if ingredient.quantity == nil && !ingredient.originalText.isEmpty {
                Text(ingredient.originalText).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        Section("instructions") {
          ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: 16) {
              Text("\(index + 1)").font(.headline).foregroundStyle(.tint)
                .frame(minWidth: 24, alignment: .leading).accessibilityHidden(true)
              Text(step).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 8)
              .accessibilityLabel(Text("recipe_step \(index + 1) \(step)"))
          }
        }
        if !recipe.notes.isEmpty { Section("notes") { Text(recipe.notes) } }
        if let source = recipe.sourceURL, let url = URL(string: source),
          ["https", "http"].contains(url.scheme ?? "")
        {
          Section("source") { Link(source, destination: url) }
        }
        Section { Button("delete_recipe", role: .destructive) { deleting = true } }
      }.navigationTitle(recipe.title).navigationBarTitleDisplayMode(.inline)
        .onAppear { servingCount = max(1, min(100, Int(recipe.servings) ?? 2)) }
        .toolbar { Button("edit") { editing = true } }
        .sheet(isPresented: $editing) { RecipeEditor(id: id, initial: recipe) }
        .confirmationDialog(
          "delete_recipe_question", isPresented: $deleting, titleVisibility: .visible
        ) {
          Button("delete_recipe", role: .destructive) {
            Task {
              if await model.save(kind: .recipe, id: id, value: recipe, delete: true) { dismiss() }
            }
          }
        }
    } else {
      ContentUnavailableView("recipe_unavailable", systemImage: "book.closed")
    }
  }
}
struct RecipeEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let id: UUID
  @State private var recipe: Recipe
  @State private var source = ""
  @State private var saving = false
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var preparedPhoto: Data?
  @State private var preparingPhoto = false
  @State private var photoError: String?

  init(id: UUID = UUID(), initial: Recipe = Recipe()) {
    self.id = id
    _recipe = State(initialValue: initial)
    _source = State(initialValue: initial.sourceURL ?? "")
  }
  var valid: Bool {
    !recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (Decimal(string: recipe.servings) ?? 0) > 0
      && recipe.ingredients.allSatisfy {
        !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("recipe_photo") {
          if let preparedPhoto, let image = UIImage(data: preparedPhoto) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
              .accessibilityLabel(Text("recipe_photo"))
          } else if recipe.imageID != nil {
            RecipePhotoView(imageID: recipe.imageID).frame(height: 180)
          }
          PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            Label("choose_photo", systemImage: "photo.on.rectangle")
          }.disabled(preparingPhoto || saving)
          if preparingPhoto { ProgressView("preparing_photo") }
          if let photoError { Text(photoError).foregroundStyle(.red) }
          if preparedPhoto != nil || recipe.imageID != nil {
            Button("remove_photo", role: .destructive) {
              preparedPhoto = nil
              recipe.imageID = nil
              selectedPhoto = nil
              photoError = nil
            }.disabled(preparingPhoto || saving)
          }
          Text("photo_privacy").font(.caption).foregroundStyle(.secondary)
        }
        Section("recipe") {
          TextField("recipe_title", text: $recipe.title)
          TextField("description", text: $recipe.description, axis: .vertical)
          TextField("servings", text: $recipe.servings).keyboardType(.decimalPad)
        }
        Section("ingredients") {
          ForEach($recipe.ingredients) { $item in
            VStack(alignment: .leading) {
              TextField("ingredient_name", text: $item.name)
              HStack {
                TextField(
                  "quantity",
                  text: Binding(
                    get: { item.quantity ?? "" }, set: { item.quantity = $0.isEmpty ? nil : $0 })
                ).keyboardType(.decimalPad)
                TextField("unit", text: $item.unit)
              }
              TextField("original_text", text: $item.originalText)
              TextField("preparation", text: $item.preparation)
            }
          }.onDelete { recipe.ingredients.remove(atOffsets: $0) }.onMove {
            recipe.ingredients.move(fromOffsets: $0, toOffset: $1)
          }
          Button("add_ingredient") { recipe.ingredients.append(Ingredient()) }
        }
        Section("instructions") {
          ForEach(recipe.steps.indices, id: \.self) { index in
            TextField("step", text: $recipe.steps[index], axis: .vertical)
          }
          .onDelete { recipe.steps.remove(atOffsets: $0) }.onMove {
            recipe.steps.move(fromOffsets: $0, toOffset: $1)
          }
          Button("add_step") { recipe.steps.append("") }
        }
        Section("personal") {
          TextField("notes", text: $recipe.notes, axis: .vertical)
          Picker(
            "rating",
            selection: Binding(
              get: { recipe.rating ?? 0 }, set: { recipe.rating = $0 == 0 ? nil : $0 })
          ) {
            Text("unrated").tag(0)
            ForEach(1...5, id: \.self) { Text(String(repeating: "★", count: $0)).tag($0) }
          }
        }
        Section("source") {
          TextField("source_url", text: $source).keyboardType(.URL).textInputAutocapitalization(
            .never)
        }
      }.navigationTitle("recipe_editor")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("save") {
              saving = true
              recipe.sourceURL = source.isEmpty ? nil : source
              recipe.steps.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
              Task {
                if await model.saveRecipe(id: id, recipe: recipe, photo: preparedPhoto) {
                  dismiss()
                }
                saving = false
              }
            }.disabled(!valid || saving || preparingPhoto)
          }
          ToolbarItem(placement: .bottomBar) { EditButton() }
        }
    }.safeAreaInset(edge: .bottom) { OperationErrorNotice() }
      .interactiveDismissDisabled(saving || preparingPhoto)
      .task(id: selectedPhoto) {
        guard let selectedPhoto else { return }
        preparingPhoto = true
        photoError = nil
        defer { preparingPhoto = false }
        do {
          guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
            throw StoreError.invalidPhoto
          }
          let result = try await Task.detached(priority: .userInitiated) {
            try PhotoPreparation.prepare(data)
          }.value
          try Task.checkCancellation()
          preparedPhoto = result
        } catch is CancellationError {
        } catch { photoError = String(localized: "photo_invalid") }
      }
  }
}
