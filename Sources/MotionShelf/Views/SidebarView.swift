import SwiftUI

struct SidebarView: View {
    @ObservedObject var library: EffectLibrary
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    /// 從右鍵「移到新分類…」打開時，建立後把這個效果移進去
    @State private var movingEffect: Effect?
    /// 右鍵「刪除效果…」選到的效果，確認後才丟到垃圾桶
    @State private var trashing: Effect?
    @State private var trashError: String?

    enum Filter: Hashable {
        case all
        case favorites
        case category(String)
    }

    var body: some View {
        VStack(spacing: 8) {
            InboxButton(inbox: library.inbox)

            PlasticTextField(placeholder: L("搜尋名稱或 prompt", "Search names or prompts"), text: $query, yellow: true)

            HStack(spacing: 6) {
                BrickMenu(title: filterTitle) {
                    Picker(L("分類", "Category"), selection: $filter) {
                        Text(L("全部（\(library.effects.count)）", "All (\(library.effects.count))")).tag(Filter.all)
                        Text(L("★ 收藏（\(library.favorites.count)）", "★ Favorites (\(library.favorites.count))")).tag(Filter.favorites)
                        Divider()
                        ForEach(library.categories, id: \.self) { category in
                            Text("\(Effect.displayName(category)) (\(count(in: category)))").tag(Filter.category(category))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if case .category(let name) = filter, library.isCustom(name), count(in: name) == 0 {
                    PanelButton(symbol: "trash", help: L("刪除這個空的分類", "Delete this empty category")) {
                        library.removeCategory(name)
                        filter = .all
                    }
                }
                PanelButton(symbol: "plus", help: L("新增分類", "New category")) {
                    movingEffect = nil
                    showNewCategory = true
                }
                .popover(isPresented: $showNewCategory, arrowEdge: .bottom) { newCategoryForm }
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { effect in
                        EffectRow(
                            effect: effect,
                            isSelected: library.selectedID == effect.id,
                            isFavorite: library.isFavorite(effect),
                            toggleFavorite: { library.toggleFavorite(effect) }
                        )
                        .onTapGesture { select(effect) }
                        .contextMenu { menu(for: effect) }
                        Seam().padding(.horizontal, 6)
                    }
                    if !library.problems.isEmpty {
                        Text(L("無法讀取", "Couldn't load")).font(.caption.bold()).foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        ForEach(library.problems) { problem in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(problem.id, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text(problem.message)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(LinearGradient(colors: [.black.opacity(0.18), .white.opacity(0.7)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .overlay {
                if filtered.isEmpty && library.problems.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .confirmationDialog(
            L("要把「", "Move \"") + (trashing?.name ?? "") + L("」丟到垃圾桶嗎？", "\" to the Trash?"),
            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }),
            titleVisibility: .visible,
            presenting: trashing
        ) { effect in
            Button(L("丟到垃圾桶", "Move to Trash"), role: .destructive) { trashError = library.trash(effect) }
            Button(L("取消", "Cancel"), role: .cancel) {}
        } message: { _ in
            Text(L("整個效果資料夾會移到垃圾桶，需要時可以從垃圾桶還原。", "The whole effect folder goes to the Trash. You can put it back from there."))
        }
        .alert(L("沒有刪除", "Not deleted"), isPresented: Binding(get: { trashError != nil }, set: { if !$0 { trashError = nil } })) {
            Button(L("好", "OK")) {}
        } message: {
            Text(trashError ?? "")
        }
    }

    /// 點效果一定回到播放頁面，就算點的是已經選取的那個
    private func select(_ effect: Effect) {
        library.selectedID = effect.id
        library.inbox.isOpen = false
    }

    @ViewBuilder
    private func menu(for effect: Effect) -> some View {
        Menu(L("移到分類", "Move to Category")) {
            ForEach(library.categories, id: \.self) { category in
                Button {
                    library.move(effect, to: category)
                } label: {
                    if category == effect.category { Label(Effect.displayName(category), systemImage: "checkmark") } else { Text(Effect.displayName(category)) }
                }
                .disabled(category == effect.category)
            }
            Divider()
            Button(L("移到新分類…", "Move to New Category…")) {
                movingEffect = effect
                showNewCategory = true
            }
        }
        Button(L("匯出效果…", "Export Effect…")) { EffectTransfer.export(effect) }
        Button(library.isFavorite(effect) ? L("取消收藏", "Remove from Favorites") : L("加入收藏", "Add to Favorites")) { library.toggleFavorite(effect) }
        Divider()
        Button(L("刪除效果…", "Delete Effect…"), role: .destructive) { trashing = effect }
            .disabled(!library.canTrash(effect))
    }

    private var newCategoryForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            BubbleTitle(text: movingEffect.map { L("把「\($0.name)」移到新分類", "Move \"\($0.name)\" to a new category") } ?? L("新增分類", "New category"), symbol: "sparkles", tone: .red)
            TextField(L("分類名稱，例如：婚禮", "Category name, e.g. Wedding"), text: $newCategoryName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(createCategory)
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { showNewCategory = false }
                    .buttonStyle(PlasticButtonStyle(tone: .gray))
                Button(L("建立", "Create"), action: createCategory)
                    .buttonStyle(PlasticButtonStyle())
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .fontDesign(.rounded)
        .foregroundStyle(Theme.ink)
        .background(Theme.cream)
    }

    private func createCategory() {
        guard let name = library.addCategory(newCategoryName) else { return }
        if let effect = movingEffect { library.move(effect, to: name) }
        filter = .category(name)
        newCategoryName = ""
        movingEffect = nil
        showNewCategory = false
    }

    private func count(in category: String) -> Int {
        library.effects.filter { $0.category == category }.count
    }

    private var filtered: [Effect] {
        library.effects.filter { effect in
            switch filter {
            case .all: break
            case .favorites: guard library.isFavorite(effect) else { return false }
            case .category(let category): guard effect.category == category else { return false }
            }
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return true }
            return [effect.name, effect.id, Effect.displayName(effect.category), effect.source]
                .contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    private var filterTitle: String {
        switch filter {
        case .all: L("全部（\(library.effects.count)）", "All (\(library.effects.count))")
        case .favorites: L("★ 收藏（\(library.favorites.count)）", "★ Favorites (\(library.favorites.count))")
        case .category(let category): "\(Effect.displayName(category)) (\(count(in: category)))"
        }
    }

    private var emptyMessage: String {
        if library.effects.isEmpty { return L("effects 資料夾是空的\n把效果資料夾放進去就會出現", "The effects folder is empty\nPut effect folders in it and they'll show up") }
        if !query.isEmpty { return L("找不到「\(query)」", "No results for \"\(query)\"") }
        return L("這個分類還沒有效果\n在效果上按右鍵可以移進來", "No effects in this category yet\nRight-click an effect to move it here")
    }
}

/// 側欄最下面一排：重新掃描、打開資料夾、效果總數
struct SidebarFooter: View {
    @ObservedObject var library: EffectLibrary

    var body: some View {
        HStack(spacing: 6) {
            PanelButton(symbol: "arrow.clockwise", help: L("重新掃描效果資料夾", "Rescan the effects folder"), action: library.reload)
            PanelButton(symbol: "folder", help: L("在 Finder 中打開效果資料夾", "Open the effects folder in Finder"), action: library.revealInFinder)
            PanelButton(symbol: "square.and.arrow.down", help: L("匯入效果（.mseffect）", "Import effects (.mseffect)")) {
                EffectTransfer.chooseAndImport(into: library)
            }
            PanelButton(symbol: "square.and.arrow.up", help: L("匯出目前選取的效果，分享給別人", "Export the selected effect to share it")) {
                if let effect = library.selected { EffectTransfer.export(effect) }
            }
            Spacer(minLength: 4)
            Text(L("\(library.effects.count) 個效果", "\(library.effects.count) effects"))
                .font(.callout.weight(.bold))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 14)
    }
}

private struct EffectRow: View {
    let effect: Effect
    let isSelected: Bool
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(effect.name).font(.callout.weight(.bold)).lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white : Theme.ink)
                Text("\(Effect.displayName(effect.category)) · \(String(format: "%.1f", effect.manifest.duration)) \(L("秒", "s"))")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.88) : Theme.inkSoft)
            }
            Spacer(minLength: 0)
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? (isSelected ? Theme.yellow : Theme.yellowDeep) : (isSelected ? Color.white.opacity(0.8) : Theme.inkSoft.opacity(0.6)))
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? L("取消收藏", "Remove from Favorites") : L("加入收藏", "Add to Favorites"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            if isSelected {
                PlasticFill(shape: RoundedRectangle(cornerRadius: 9, style: .continuous), top: Theme.green, bottom: Theme.greenDeep, depth: 4)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let image = effect.thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "sparkles").foregroundStyle(Theme.redDeep)
            }
        }
        .frame(width: 52, height: 29)
        .background(Color(rgb: 0x302C28))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.black.opacity(0.5), lineWidth: 1))
    }
}

private struct InboxButton: View {
    @ObservedObject var inbox: Inbox

    var body: some View {
        Button {
            inbox.isOpen.toggle()
        } label: {
            HStack {
                Label(L("收件匣", "Inbox"), systemImage: "envelope.fill")
                Spacer()
                if !inbox.pending.isEmpty {
                    Text("\(inbox.pending.count)")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.redDeep)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(.white, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlasticButtonStyle(tone: .red))
        .brightness(inbox.isOpen ? 0.08 : 0)
        .help(L("收集網路上看到的 motion prompt", "Collect motion prompts you find online"))
    }
}
