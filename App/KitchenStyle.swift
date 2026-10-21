import AirCookerCore
import SwiftUI

/// Native surfaces and text styles adapt to appearance and Dynamic Type.
enum KitchenStyle {
  static let accent = Color("AccentColor")
  static let background = Color(uiColor: .systemGroupedBackground)
  static let surface = Color(uiColor: .secondarySystemGroupedBackground)
  static let placeholder = Color(uiColor: .tertiarySystemFill)
  static let radius: CGFloat = 16
  static func symbol(for category: String) -> String {
    switch category {
    case "breakfast": return "sunrise"
    case "lunch": return "sun.max"
    default: return "moon"
    }
  }
}

/// The system owns refraction and appearance. Accessibility settings use an
/// opaque semantic surface instead of relying on the backdrop for contrast.
private struct KitchenGlass<Surface: Shape>: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  let shape: Surface
  func body(content: Content) -> some View {
    if reduceTransparency || contrast == .increased {
      content.background(KitchenStyle.surface, in: shape)
    } else {
      content.glassEffect(.regular, in: shape)
    }
  }
}

extension View {
  func kitchenGlass<Surface: Shape>(in shape: Surface) -> some View {
    modifier(KitchenGlass(shape: shape))
  }
}

struct RecipeCard: View {
  let recipe: Recipe
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      RecipePhotoView(imageID: recipe.imageID).aspectRatio(3 / 2, contentMode: .fit)
      VStack(alignment: .leading, spacing: 8) {
        Text(recipe.title).font(.headline).foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(alignment: .firstTextBaseline) {
          Text("ingredient_count \(recipe.ingredients.count)")
          Spacer(minLength: 6)
          if let rating = recipe.rating {
            Label(String(rating), systemImage: "star.fill").labelStyle(.titleAndIcon)
          }
        }.font(.caption).foregroundStyle(.secondary)
      }.padding(16)
    }
    .background(KitchenStyle.surface)
    .clipShape(RoundedRectangle(cornerRadius: KitchenStyle.radius))
    .contentShape(RoundedRectangle(cornerRadius: KitchenStyle.radius))
    .accessibilityElement(children: .combine)
  }
}

struct MealRow: View {
  @Environment(AppModel.self) private var model
  let item: MealOccurrence
  var body: some View {
    HStack(spacing: 14) {
      RecipePhotoView(imageID: model.recipe(item.meal.recipeID)?.imageID)
        .frame(width: 72, height: 76).clipShape(RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 6) {
        Label(
          LocalizedStringKey(item.meal.category),
          systemImage: KitchenStyle.symbol(for: item.meal.category)
        )
        .font(.caption).foregroundStyle(.secondary)
        Text(model.title(item.meal)).font(.headline).foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
        if item.meal.leftoverID != nil {
          Text("leftovers").font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }.padding(.vertical, 8).contentShape(Rectangle())
      .accessibilityElement(children: .combine)
  }
}
