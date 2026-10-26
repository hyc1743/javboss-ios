import SwiftUI

// MARK: - 女优详情

@MainActor
final class IdolDetailVM: ObservableObject {
    @Published var idol: JavIdolSummary?
    @Published var loading = true
    @Published var errorMessage: String?

    let idolId: Int64

    init(idolId: Int64) {
        self.idolId = idolId
    }

    func load() async {
        loading = true
        do {
            idol = try await Repository(api: AppState.shared.api).getIdol(id: idolId)
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }
}

struct IdolDetailView: View {
    @StateObject private var vm: IdolDetailVM
    @State private var showEdit = false
    @State private var showFavorite = false
    @State private var showCoverPicker = false
    @State private var showMerge = false
    @State private var showWeb: WebTarget?

    init(idolId: Int64) {
        _vm = StateObject(wrappedValue: IdolDetailVM(idolId: idolId))
    }

    var body: some View {
        Group {
            if vm.loading && vm.idol == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let idol = vm.idol {
                content(idol)
            } else {
                EmptyPlaceholder(icon: "person.crop.circle.badge.exclamationmark", text: "女优不存在")
            }
        }
        .background(Color(white: 0.09))
        .navigationTitle(vm.idol?.displayName ?? "女优")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showFavorite = true
                    } label: {
                        Label("收藏夹", systemImage: "heart")
                    }
                    Button {
                        showCoverPicker = true
                    } label: {
                        Label("选择封面", systemImage: "photo")
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Label("编辑信息", systemImage: "square.and.pencil")
                    }
                    Button {
                        showMerge = true
                    } label: {
                        Label("????", systemImage: "arrow.triangle.merge")
                    }
                    Divider()
                    Button {
                        Task {
                            do {
                                guard let idol = vm.idol, let code = idol.coverCode, !code.isEmpty else {
                                    vm.errorMessage = "该女优暂无封面番号，无法查询 JavDB"
                                    return
                                }
                                let url = try await Repository(api: AppState.shared.api)
                                    .idolJavdbUrl(code: code, name: idol.name)
                                showWeb = WebTarget(url: url)
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("JavDB 页面", systemImage: "globe")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await vm.load() }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .sheet(isPresented: $showEdit) {
            IdolEditView(idolId: vm.idolId, current: vm.idol) { Task { await vm.load() } }
        }
        .sheet(isPresented: $showFavorite) {
            FavoritePickerSheet(entity: .idol, itemId: vm.idolId, title: vm.idol?.displayName ?? "收藏夹") {
                Task { await vm.load() }
            }
        }
        .sheet(isPresented: $showCoverPicker) {
            IdolCoverPickerView(idolId: vm.idolId) { Task { await vm.load() } }
        }
        .sheet(isPresented: $showMerge) {
            IdolMergeSheet(canonicalId: vm.idolId) { Task { await vm.load() } }
        }
        .sheet(item: $showWeb) { target in
            WebViewer(url: target.url)
        }
    }

    private func content(_ idol: JavIdolSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: URL(string: AppState.shared.api.idolCoverUrl(id: idol.id) ?? ""),
                                contentMode: .fit)
                        .frame(width: 110, height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(idol.displayName)
                            .font(.title3.bold())
                        if let jp = idol.japaneseName, !jp.isEmpty {
                            Text(jp).font(.subheadline)
                        }
                        if let roman = idol.romanName, !roman.isEmpty {
                            Text(roman).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            Text("\(Fmt.count(idol.workCount)) 作品")
                            if let fav = idol.favoriteCount, fav > 0 {
                                Text("♥ \(Fmt.count(Int64(fav)))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)

                // 档案
                if let height = idol.heightCm, let bust = idol.bust, let waist = idol.waist, let hips = idol.hips {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("档案")
                            .font(.subheadline.bold())
                        HStack(spacing: 14) {
                            ProfileStat(label: "身高", value: "\(height)cm")
                            ProfileStat(label: "胸围", value: "\(bust)cm")
                            ProfileStat(label: "腰围", value: "\(waist)cm")
                            ProfileStat(label: "臀围", value: "\(hips)cm")
                            if let cup = idol.cup {
                                ProfileStat(label: "罩杯", value: "Cup \(cup)")
                            }
                        }
                        .font(.caption)
                        if let birth = idol.birthDate, !birth.isEmpty {
                            Text("生日：\(Fmt.date(birth))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }

                // 别名
                if let aliases = idol.aliases, !aliases.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("别名")
                            .font(.subheadline.bold())
                        ChipFlowLayout(chips: aliases)
                    }
                    .padding(.horizontal)
                }

                // 作品列表
                VStack(alignment: .leading, spacing: 8) {
                    Text("出演作品")
                        .font(.subheadline.bold())
                    IdolWorksList(idolId: idol.id)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}

struct ProfileStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct IdolWorksList: View {
    let idolId: Int64
    @State private var works: [Jav] = []
    @State private var loading = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        Group {
            if loading && works.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if works.isEmpty {
                Text("暂无作品")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(works) { jav in
                        NavigationLink {
                            WorkDetailView(javId: jav.id)
                        } label: {
                            WorkCard(jav: jav)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            if works.isEmpty {
                loading = true
                do {
                    works = try await Repository(api: AppState.shared.api).searchJav(
                        limit: 100, offset: 0, idolIds: [idolId]).items
                } catch {
                    errorMessage = error.localizedDescription
                }
                loading = false
            }
        }
    }
}

// MARK: - 女优编辑

struct IdolEditView: View {
    let idolId: Int64
    let current: JavIdolSummary?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var romanName = ""
    @State private var japaneseName = ""
    @State private var chineseName = ""
    @State private var heightCm = ""
    @State private var birthDate = ""
    @State private var bust = ""
    @State private var waist = ""
    @State private var hips = ""
    @State private var cup = ""
    @State private var aliases = ""
    @State private var errorMessage: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("名称", text: $name)
                    TextField("中文名", text: $chineseName)
                    TextField("日文名", text: $japaneseName)
                    TextField("罗马名", text: $romanName)
                    TextField("别名（逗号分隔）", text: $aliases)
                }
                Section("档案") {
                    TextField("身高 cm", text: $heightCm).keyboardType(.numberPad)
                    TextField("出生日期 YYYY-MM-DD", text: $birthDate)
                    TextField("胸围 cm", text: $bust).keyboardType(.numberPad)
                    TextField("腰围 cm", text: $waist).keyboardType(.numberPad)
                    TextField("臀围 cm", text: $hips).keyboardType(.numberPad)
                    TextField("罩杯（1-11）", text: $cup).keyboardType(.numberPad)
                }
            }
            .navigationTitle("编辑女优")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            do {
                                _ = try await Repository(api: AppState.shared.api).updateIdol(
                                    id: idolId,
                                    request: JavIdolUpdateRequest(
                                        name: name, romanName: romanName, japaneseName: japaneseName,
                                        chineseName: chineseName, heightCm: Int(heightCm),
                                        birthDate: birthDate, bust: Int(bust), waist: Int(waist),
                                        hips: Int(hips), cup: Int(cup),
                                        aliases: aliases.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                    ))
                                onSaved()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
            .onAppear {
                name = current?.name ?? ""
                romanName = current?.romanName ?? ""
                japaneseName = current?.japaneseName ?? ""
                chineseName = current?.chineseName ?? ""
                heightCm = current?.heightCm.map(String.init) ?? ""
                birthDate = current?.birthDate.map { String($0.prefix(10)) } ?? ""
                bust = current?.bust.map(String.init) ?? ""
                waist = current?.waist.map(String.init) ?? ""
                hips = current?.hips.map(String.init) ?? ""
                cup = current?.cup.map(String.init) ?? ""
                aliases = (current?.aliases ?? []).joined(separator: ", ")
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}

// MARK: - 女优封面选择

@MainActor
final class IdolCoverPickerVM: ObservableObject {
    @Published var options: [JavIdolCoverOption] = []
    @Published var loading = true
    @Published var errorMessage: String?

    let idolId: Int64

    init(idolId: Int64) {
        self.idolId = idolId
    }

    func load() async {
        loading = true
        do {
            options = try await Repository(api: AppState.shared.api).idolCoverOptions(id: idolId)
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

struct IdolCoverPickerView: View {
    let idolId: Int64
    let onSaved: () -> Void

    @StateObject private var vm: IdolCoverPickerVM
    @Environment(\.dismiss) private var dismiss

    init(idolId: Int64, onSaved: @escaping () -> Void) {
        self.idolId = idolId
        self.onSaved = onSaved
        _vm = StateObject(wrappedValue: IdolCoverPickerVM(idolId: idolId))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.options) { option in
                    Button {
                        Task {
                            do {
                                try await Repository(api: AppState.shared.api)
                                    .updateIdolCover(id: idolId, javId: option.id, cropLeft: 0.5)
                                onSaved()
                                dismiss()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            RemoteImage(url: URL(string: AppState.shared.api.javCoverUrl(code: option.code) ?? ""))
                                .frame(width: 44, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.code)
                                    .font(.subheadline.bold())
                                Text(option.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if option.solo == true {
                                Text("单体")
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.7), in: Capsule())
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("选择封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task { await vm.load() }
            .errorAlert(vm.errorMessage) { vm.errorMessage = nil }
        }
    }
}

// MARK: - 片商详情

@MainActor
final class StudioDetailVM: ObservableObject {
    @Published var studio: JavStudioSummary?
    @Published var loading = true
    @Published var errorMessage: String?

    let studioId: Int64

    init(studioId: Int64) {
        self.studioId = studioId
    }

    func load() async {
        loading = true
        do {
            studio = try await Repository(api: AppState.shared.api).getStudio(id: studioId)
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }
}

struct StudioDetailView: View {
    @StateObject private var vm: StudioDetailVM
    @State private var showEdit = false
    @State private var showFavorite = false
    @State private var showWeb: WebTarget?
    @State private var showMerge = false

    init(studioId: Int64) {
        _vm = StateObject(wrappedValue: StudioDetailVM(studioId: studioId))
    }

    var body: some View {
        Group {
            if vm.loading && vm.studio == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let studio = vm.studio {
                content(studio)
            } else {
                EmptyPlaceholder(icon: "building.2.crop.circle", text: "片商不存在")
            }
        }
        .background(Color(white: 0.09))
        .navigationTitle(vm.studio?.name ?? "片商")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showFavorite = true
                    } label: {
                        Label("收藏夹", systemImage: "heart")
                    }
                    Button {
                        showMerge = true
                    } label: {
                        Label("????", systemImage: "arrow.triangle.merge")
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Label("编辑信息", systemImage: "square.and.pencil")
                    }
                    Divider()
                    Button {
                        Task {
                            do {
                                let url = try await Repository(api: AppState.shared.api).studioJavdbUrl(studioId: vm.studioId)
                                showWeb = WebTarget(url: url)
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("JavDB 页面", systemImage: "globe")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await vm.load() }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .sheet(isPresented: $showEdit) {
            StudioEditView(studioId: vm.studioId, current: vm.studio) { Task { await vm.load() } }
        }
        .sheet(isPresented: $showFavorite) {
            FavoritePickerSheet(entity: .studio, itemId: vm.studioId, title: vm.studio?.name ?? "收藏夹") {
                Task { await vm.load() }
            }
        }
        .sheet(isPresented: $showMerge) {
            StudioMergeSheet(canonicalId: vm.studioId) { Task { await vm.load() } }
        }
        .sheet(item: $showWeb) { target in
            WebViewer(url: target.url)
        }
    }

    private func content(_ studio: JavStudioSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: URL(string: AppState.shared.api.studioCoverUrl(id: studio.id) ?? ""),
                                contentMode: .fit)
                        .frame(width: 110, height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(studio.name)
                            .font(.title3.bold())
                        Text("\(Fmt.count(studio.workCount)) 作品")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let fav = studio.favoriteCount, fav > 0 {
                            Text("♥ \(Fmt.count(Int64(fav)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)

                if let aliases = studio.aliases, !aliases.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("别名")
                            .font(.subheadline.bold())
                        ChipFlowLayout(chips: aliases)
                    }
                    .padding(.horizontal)
                }

                if let prefixes = studio.codePrefixes, !prefixes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("番号前缀")
                            .font(.subheadline.bold())
                        ChipFlowLayout(chips: prefixes.map { "\($0.prefix) (\($0.workCount))" })
                    }
                    .padding(.horizontal)
                }

                if let series = studio.series, !series.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("系列")
                            .font(.subheadline.bold())
                        ForEach(series) { s in
                            NavigationLink {
                                SeriesDetailView(seriesId: s.id)
                            } label: {
                                HStack {
                                    Text(s.displayName)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(Fmt.count(s.workCount)) 作品")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(10)
                                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("作品")
                        .font(.subheadline.bold())
                    StudioWorksList(studioId: studio.id)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}

struct StudioWorksList: View {
    let studioId: Int64
    @State private var works: [Jav] = []
    @State private var loading = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        Group {
            if loading && works.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if works.isEmpty {
                Text("暂无作品")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(works) { jav in
                        NavigationLink {
                            WorkDetailView(javId: jav.id)
                        } label: {
                            WorkCard(jav: jav)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            if works.isEmpty {
                loading = true
                works = (try? await Repository(api: AppState.shared.api).searchJav(
                    limit: 100, offset: 0, studioId: studioId).items) ?? []
                loading = false
            }
        }
    }
}

struct StudioEditView: View {
    let studioId: Int64
    let current: JavStudioSummary?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var aliases = ""
    @State private var errorMessage: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("片商名称", text: $name)
                    TextField("别名（逗号分隔）", text: $aliases)
                }
            }
            .navigationTitle("编辑片商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            do {
                                _ = try await Repository(api: AppState.shared.api).updateStudio(
                                    id: studioId,
                                    request: JavStudioUpdateRequest(
                                        name: name,
                                        aliases: aliases.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                    ))
                                onSaved()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
            .onAppear {
                name = current?.name ?? ""
                aliases = (current?.aliases ?? []).joined(separator: ", ")
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}

// MARK: - 系列详情

@MainActor
final class SeriesDetailVM: ObservableObject {
    @Published var series: JavSeriesSummary?
    @Published var loading = true
    @Published var errorMessage: String?

    let seriesId: Int64

    init(seriesId: Int64) {
        self.seriesId = seriesId
    }

    func load() async {
        loading = true
        do {
            series = try await Repository(api: AppState.shared.api).getSeries(id: seriesId)
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }
}

struct SeriesDetailView: View {
    @StateObject private var vm: SeriesDetailVM
    @State private var showEdit = false
    @State private var showFavorite = false
    @State private var showWeb: WebTarget?

    init(seriesId: Int64) {
        _vm = StateObject(wrappedValue: SeriesDetailVM(seriesId: seriesId))
    }

    var body: some View {
        Group {
            if vm.loading && vm.series == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let series = vm.series {
                content(series)
            } else {
                EmptyPlaceholder(icon: "list.bullet.rectangle.portrait", text: "系列不存在")
            }
        }
        .background(Color(white: 0.09))
        .navigationTitle(vm.series?.displayName ?? "系列")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showFavorite = true
                    } label: {
                        Label("收藏夹", systemImage: "heart")
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Label("编辑译名", systemImage: "square.and.pencil")
                    }
                    Button {
                        Task {
                            do {
                                try await Repository(api: AppState.shared.api).translateSeriesName(id: vm.seriesId)
                                await vm.load()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("翻译系列名", systemImage: "character.bubble")
                    }
                    Divider()
                    Button {
                        Task {
                            do {
                                let url = try await Repository(api: AppState.shared.api).seriesJavdbUrl(seriesId: vm.seriesId)
                                showWeb = WebTarget(url: url)
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("JavDB 页面", systemImage: "globe")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await vm.load() }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .sheet(isPresented: $showEdit) {
            SeriesEditView(seriesId: vm.seriesId, current: vm.series) { Task { await vm.load() } }
        }
        .sheet(isPresented: $showFavorite) {
            FavoritePickerSheet(entity: .series, itemId: vm.seriesId, title: vm.series?.displayName ?? "收藏夹") {
                Task { await vm.load() }
            }
        }
        .sheet(item: $showWeb) { target in
            WebViewer(url: target.url)
        }
    }

    private func content(_ series: JavSeriesSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: URL(string: AppState.shared.api.seriesCoverUrl(id: series.id) ?? ""),
                                contentMode: .fit)
                        .frame(width: 110, height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(series.displayName)
                            .font(.title3.bold())
                        if let zh = series.zhName, !zh.isEmpty, zh != series.name {
                            Text(series.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Fmt.count(series.workCount)) 作品")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let studioName = series.studioName, !studioName.isEmpty {
                            Text(studioName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let fav = series.favoriteCount, fav > 0 {
                            Text("♥ \(Fmt.count(Int64(fav)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("作品")
                        .font(.subheadline.bold())
                    SeriesWorksList(seriesId: series.id)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}

struct SeriesWorksList: View {
    let seriesId: Int64
    @State private var works: [Jav] = []
    @State private var loading = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        Group {
            if loading && works.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if works.isEmpty {
                Text("暂无作品")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(works) { jav in
                        NavigationLink {
                            WorkDetailView(javId: jav.id)
                        } label: {
                            WorkCard(jav: jav)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            if works.isEmpty {
                loading = true
                works = (try? await Repository(api: AppState.shared.api).searchJav(
                    limit: 100, offset: 0, seriesId: seriesId).items) ?? []
                loading = false
            }
        }
    }
}

struct SeriesEditView: View {
    let seriesId: Int64
    let current: JavSeriesSummary?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var zhName = ""
    @State private var errorMessage: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("系列名", text: $name)
                    TextField("中文译名", text: $zhName)
                }
            }
            .navigationTitle("编辑系列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            do {
                                _ = try await Repository(api: AppState.shared.api).updateSeries(
                                    id: seriesId,
                                    request: JavSeriesUpdateRequest(name: name, zhName: zhName))
                                onSaved()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
            .onAppear {
                name = current?.name ?? ""
                zhName = current?.zhName ?? ""
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}


struct IdolMergeSheet: View {
    let canonicalId: Int64
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [JavIdolSummary] = []
    @State private var selected: Set<Int64> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(items) { item in
                Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                    if value { selected.insert(item.id) } else { selected.remove(item.id) }
                })) {
                    Text(item.displayName)
                }
            }
            .navigationTitle("????")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("??") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("??") {
                        Task {
                            do {
                                try await Repository(api: AppState.shared.api).mergeIdols(canonicalId: canonicalId, mergeIds: Array(selected))
                                onDone()
                                dismiss()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task {
                items = ((try? await Repository(api: AppState.shared.api).listIdols(limit: 200, offset: 0))?.items ?? []).filter { $0.id != canonicalId }
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}

struct StudioMergeSheet: View {
    let canonicalId: Int64
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [JavStudioSummary] = []
    @State private var selected: Set<Int64> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(items) { item in
                Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                    if value { selected.insert(item.id) } else { selected.remove(item.id) }
                })) {
                    Text(item.name)
                }
            }
            .navigationTitle("????")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("??") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("??") {
                        Task {
                            do {
                                try await Repository(api: AppState.shared.api).mergeStudios(canonicalId: canonicalId, mergeIds: Array(selected))
                                onDone()
                                dismiss()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task {
                items = ((try? await Repository(api: AppState.shared.api).listStudios(limit: 200, offset: 0))?.items ?? []).filter { $0.id != canonicalId }
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}
