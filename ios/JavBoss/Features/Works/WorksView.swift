import SwiftUI

enum WorksPerspective: String, CaseIterable, Identifiable {
    case works
    case idols
    case studios
    case series

    var id: String { rawValue }
    var label: String {
        switch self {
        case .works: return "作品"
        case .idols: return "女优"
        case .studios: return "片商"
        case .series: return "系列"
        }
    }
}

struct WorksView: View {
    @State private var perspective: WorksPerspective = .works

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("视角", selection: $perspective) {
                    ForEach(WorksPerspective.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch perspective {
                case .works:
                    WorksListView()
                case .idols:
                    IdolsListView()
                case .studios:
                    StudiosListView()
                case .series:
                    SeriesListView()
                }
            }
            .background(Color(white: 0.09))
            .navigationTitle("作品")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 作品列表

@MainActor
final class WorksListVM: PagedListVM<Jav> {
    var search = ""
    var sort = ""
    var idolIds: [Int64] = []
    var tagIds: [Int64] = []
    var studioId: Int64?
    var seriesId: Int64?
    var prefix = ""
    var solo = false
    var seed: Int64?
    var favoriteGroupId: Int64?
    var ratingMin: Double?
    var ratingMax: Double?

    override func fetchPage(offset: Int) async throws -> ([Jav], Int) {
        let res = try await Repository(api: AppState.shared.api).searchJav(
            limit: pageSize, offset: offset, search: search, idolIds: idolIds, tagIds: tagIds,
            studioId: studioId, seriesId: seriesId, prefix: prefix, solo: solo, sort: sort,
            seed: seed, favoriteGroupId: favoriteGroupId,
            favoriteRatingMin: ratingMin, favoriteRatingMax: ratingMax)
        return (res.items, res.total)
    }
}

struct WorksListView: View {
    @StateObject private var vm = WorksListVM()
    @State private var searchText = ""
    @State private var showFilter = false
    @State private var viewMode = 0

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            SearchField(placeholder: "搜索番号 / 标题", text: $searchText) {
                vm.search = searchText
                Task { await vm.refresh() }
            }
            .padding(.horizontal)

            if vm.loading && vm.items.isEmpty {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else if vm.items.isEmpty {
                EmptyPlaceholder(icon: "square.grid.2x2", text: "没有作品")
            } else {
                ScrollView {
                    WaterfallLayout(columns: 2, spacing: 10) {
                        ForEach(vm.items) { jav in
                            NavigationLink {
                                WorkDetailView(javId: jav.id)
                            } label: {
                                WorkCard(jav: jav)
                            }
                            .buttonStyle(.plain)
                            .task {
                                await vm.loadMoreIfNeeded(current: jav)
                            }
                        }
                    }
                    .padding(.horizontal)
                    if vm.loadingMore {
                        ProgressView().padding(8)
                    }
                }
                .refreshable { await vm.refresh() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        vm.seed = Int64.random(in: 1...Int64.max)
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    Menu {
                        Picker("排序", selection: Binding(
                            get: { vm.sort },
                            set: { vm.sort = $0; Task { await vm.refresh() } }
                        )) {
                            Text("最近").tag("recent")
                            Text("最近↑").tag("recent_asc")
                            Text("番号").tag("code")
                            Text("番号↓").tag("code_desc")
                            Text("发行日期").tag("release")
                            Text("发行日期↑").tag("release_asc")
                            Text("时长").tag("duration")
                            Text("时长↑").tag("duration_asc")
                            Text("观看时长").tag("watched")
                            Text("喜爱度").tag("favorite_rating")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    Button {
                        showFilter = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            WorksFilterSheet(vm: vm)
        }
        .task {
            if vm.items.isEmpty { await vm.refresh() }
            await WatchedProgressStore.shared.refresh(javIds: vm.items.map(\.id))
        }
        .errorAlert(vm.errorMessage) { vm.clearError() }
    }
}

struct WorkCard: View {
    let jav: Jav
    @ObservedObject private var progress = WatchedProgressStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color(white: 0.15))
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: URL(string: AppState.shared.api.javCoverUrl(code: jav.code) ?? ""))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if jav.isUncensored == true {
                        Text("无码")
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.red.opacity(0.8), in: Capsule())
                            .padding(5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let rating = jav.favoriteRating, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(5)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(jav.code)
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text(jav.displayTitle)
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let release = jav.releaseUnix, release > 0 {
                        Text(Fmt.date(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(release)))))
                    }
                    if let duration = jav.durationMin, duration > 0 {
                        Text("\(duration)min")
                    }
                    let watched = progress.javTotals[jav.id] ?? jav.watchedMs ?? 0
                    if watched > 0 {
                        Text("已看\(Fmt.ms(watched))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 女优列表

@MainActor
final class IdolsListVM: PagedListVM<JavIdolSummary> {
    var search = ""
    var sort = ""
    var favoriteGroupId: Int64?
    var ranges: [String: (Int?, Int?)] = [:]

    override func fetchPage(offset: Int) async throws -> ([JavIdolSummary], Int) {
        let res = try await Repository(api: AppState.shared.api).listIdols(
            limit: pageSize, offset: offset, search: search, sort: sort,
            favoriteGroupId: favoriteGroupId, ranges: ranges)
        // 服务端 /jav/idols 返回 items/total
        return (res.items, res.total)
    }
}

struct IdolsListView: View {
    @StateObject private var vm = IdolsListVM()
    @State private var searchText = ""
    @State private var showFilter = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            SearchField(placeholder: "搜索女优（中/日/罗马名）", text: $searchText) {
                vm.search = searchText
                Task { await vm.refresh() }
            }
            .padding(.horizontal)

            if vm.loading && vm.items.isEmpty {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else if vm.items.isEmpty {
                EmptyPlaceholder(icon: "person.2", text: "没有女优")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(vm.items) { idol in
                            NavigationLink {
                                IdolDetailView(idolId: idol.id)
                            } label: {
                                IdolCard(idol: idol)
                            }
                            .buttonStyle(.plain)
                            .task { await vm.loadMoreIfNeeded(current: idol) }
                        }
                    }
                    .padding(.horizontal)
                    if vm.loadingMore {
                        ProgressView().padding(8)
                    }
                }
                .refreshable { await vm.refresh() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Menu {
                        Picker("排序", selection: Binding(
                            get: { vm.sort },
                            set: { vm.sort = $0; Task { await vm.refresh() } }
                        )) {
                            Text("作品数").tag("")
                            Text("名称").tag("name")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    Button { showFilter = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            IdolFilterSheet(vm: vm)
        }
        .task {
            if vm.items.isEmpty { await vm.refresh() }
        }
        .errorAlert(vm.errorMessage) { vm.clearError() }
    }
}

struct IdolCard: View {
    let idol: JavIdolSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color(white: 0.15))
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: URL(string: AppState.shared.api.idolCoverUrl(id: idol.id) ?? ""))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(idol.displayName)
                .font(.footnote.bold())
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("\(Fmt.count(idol.workCount)) 作品")
                if let height = idol.heightCm {
                    Text("\(height)cm")
                }
                if let cup = idol.cup {
                    Text("Cup \(cup)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

// MARK: - 片商列表

@MainActor
final class StudiosListVM: PagedListVM<JavStudioSummary> {
    var search = ""
    var favoriteGroupId: Int64?

    override func fetchPage(offset: Int) async throws -> ([JavStudioSummary], Int) {
        let res = try await Repository(api: AppState.shared.api).listStudios(
            limit: pageSize, offset: offset, search: search, favoriteGroupId: favoriteGroupId)
        return (res.items, res.total)
    }
}

struct StudiosListView: View {
    @StateObject private var vm = StudiosListVM()
    @State private var searchText = ""

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            SearchField(placeholder: "搜索片商", text: $searchText) {
                vm.search = searchText
                Task { await vm.refresh() }
            }
            .padding(.horizontal)

            if vm.loading && vm.items.isEmpty {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else if vm.items.isEmpty {
                EmptyPlaceholder(icon: "building.2", text: "没有片商")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(vm.items) { studio in
                            NavigationLink {
                                StudioDetailView(studioId: studio.id)
                            } label: {
                                StudioCard(studio: studio)
                            }
                            .buttonStyle(.plain)
                            .task { await vm.loadMoreIfNeeded(current: studio) }
                        }
                    }
                    .padding(.horizontal)
                    if vm.loadingMore {
                        ProgressView().padding(8)
                    }
                }
                .refreshable { await vm.refresh() }
            }
        }
        .task {
            if vm.items.isEmpty { await vm.refresh() }
        }
        .errorAlert(vm.errorMessage) { vm.clearError() }
    }
}

struct StudioCard: View {
    let studio: JavStudioSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color(white: 0.15))
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: URL(string: AppState.shared.api.studioCoverUrl(id: studio.id) ?? ""))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(studio.name)
                .font(.footnote.bold())
                .lineLimit(2)
            Text("\(Fmt.count(studio.workCount)) 作品")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 系列列表

@MainActor
final class SeriesListVM: PagedListVM<JavSeriesSummary> {
    var search = ""
    var favoriteGroupId: Int64?

    override func fetchPage(offset: Int) async throws -> ([JavSeriesSummary], Int) {
        let res = try await Repository(api: AppState.shared.api).listSeries(
            limit: pageSize, offset: offset, search: search, favoriteGroupId: favoriteGroupId)
        return (res.items, res.total)
    }
}

struct SeriesListView: View {
    @StateObject private var vm = SeriesListVM()
    @State private var searchText = ""

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            SearchField(placeholder: "搜索系列", text: $searchText) {
                vm.search = searchText
                Task { await vm.refresh() }
            }
            .padding(.horizontal)

            if vm.loading && vm.items.isEmpty {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else if vm.items.isEmpty {
                EmptyPlaceholder(icon: "list.bullet.rectangle", text: "没有系列")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(vm.items) { series in
                            NavigationLink {
                                SeriesDetailView(seriesId: series.id)
                            } label: {
                                SeriesCard(series: series)
                            }
                            .buttonStyle(.plain)
                            .task { await vm.loadMoreIfNeeded(current: series) }
                        }
                    }
                    .padding(.horizontal)
                    if vm.loadingMore {
                        ProgressView().padding(8)
                    }
                }
                .refreshable { await vm.refresh() }
            }
        }
        .task {
            if vm.items.isEmpty { await vm.refresh() }
        }
        .errorAlert(vm.errorMessage) { vm.clearError() }
    }
}

struct SeriesCard: View {
    let series: JavSeriesSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color(white: 0.15))
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: URL(string: AppState.shared.api.seriesCoverUrl(id: series.id) ?? ""))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(series.displayName)
                .font(.footnote.bold())
                .lineLimit(2)
            HStack(spacing: 6) {
                Text("\(Fmt.count(series.workCount)) 作品")
                if let studioName = series.studioName, !studioName.isEmpty {
                    Text(studioName)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

extension JavSeriesSummary {
    var displayName: String {
        if let zh = zhName, !zh.isEmpty { return zh }
        return name
    }
}

// MARK: - 作品筛选

@MainActor
final class WorksFilterOptionsVM: ObservableObject {
    @Published var options: JavFilterOptions?
    @Published var loading = false
    @Published var errorMessage: String?

    var prefixSearch = ""
    var idolSearch = ""
    var tagSearch = ""
    var studioSearch = ""
    var seriesSearch = ""

    func load(vm: WorksListVM) async {
        loading = true
        do {
            options = try await Repository(api: AppState.shared.api).listJavFilterOptions(
                search: vm.search,
                idolIds: vm.idolIds, tagIds: vm.tagIds,
                studioId: vm.studioId, seriesId: vm.seriesId,
                prefix: vm.prefix, solo: vm.solo, favoriteGroupId: vm.favoriteGroupId,
                optionSearches: [
                    "prefix_search": prefixSearch,
                    "idol_search": idolSearch,
                    "tag_search": tagSearch,
                    "studio_search": studioSearch,
                    "series_search": seriesSearch,
                ])
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

struct WorksFilterSheet: View {
    @ObservedObject var vm: WorksListVM
    @StateObject private var options = WorksFilterOptionsVM()
    @Environment(\.dismiss) private var dismiss

    @State private var solo = false
    @State private var selectedIdols: Set<Int64> = []
    @State private var selectedTags: Set<Int64> = []
    @State private var selectedStudio: Int64?
    @State private var selectedSeries: Int64?
    @State private var selectedPrefix: String = ""
    @State private var favoriteGroupId: Int64?
    @State private var ratingMin = ""
    @State private var ratingMax = ""
    @State private var favoriteGroups: [FavoriteGroupSummary] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("片商") {
                    Picker("片商", selection: Binding(
                        get: { selectedStudio ?? 0 },
                        set: { selectedStudio = $0 == 0 ? nil : $0 }
                    )) {
                        Text("全部").tag(Int64(0))
                        ForEach(options.options?.studios ?? []) { studio in
                            Text(studio.name).tag(studio.id)
                        }
                    }
                }
                Section("系列") {
                    Picker("系列", selection: Binding(
                        get: { selectedSeries ?? 0 },
                        set: { selectedSeries = $0 == 0 ? nil : $0 }
                    )) {
                        Text("全部").tag(Int64(0))
                        ForEach(options.options?.series ?? []) { series in
                            Text(series.displayName).tag(series.id)
                        }
                    }
                }
                Section("番号前缀") {
                    Picker("前缀", selection: $selectedPrefix) {
                        Text("全部").tag("")
                        ForEach(options.options?.prefixes ?? [], id: \.prefix) { prefix in
                            Text(prefix.prefix).tag(prefix.prefix)
                        }
                    }
                }
                Section("女优") {
                    ForEach(options.options?.idols ?? []) { idol in
                        Button {
                            if selectedIdols.contains(idol.id) {
                                selectedIdols.remove(idol.id)
                            } else {
                                selectedIdols.insert(idol.id)
                            }
                        } label: {
                            HStack {
                                Text(idol.displayName)
                                Spacer()
                                if selectedIdols.contains(idol.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("标签") {
                    ForEach(options.options?.tags ?? []) { tag in
                        Button {
                            if selectedTags.contains(tag.id) {
                                selectedTags.remove(tag.id)
                            } else {
                                selectedTags.insert(tag.id)
                            }
                        } label: {
                            HStack {
                                Text(tag.name)
                                Spacer()
                                if selectedTags.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("其他") {
                    Toggle("仅单体", isOn: $solo)
                    Picker("收藏夹", selection: Binding(
                        get: { favoriteGroupId ?? 0 },
                        set: { favoriteGroupId = $0 == 0 ? nil : $0 }
                    )) {
                        Text("全部").tag(Int64(0))
                        ForEach(favoriteGroups) { group in
                            Text(group.name).tag(group.id)
                        }
                    }
                    HStack {
                        TextField("喜爱度最低", text: $ratingMin)
                            .keyboardType(.decimalPad)
                        Text("~")
                        TextField("最高", text: $ratingMax)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        selectedIdols.removeAll()
                        selectedTags.removeAll()
                        selectedStudio = nil
                        selectedSeries = nil
                        selectedPrefix = ""
                        solo = false
                        favoriteGroupId = nil
                        ratingMin = ""
                        ratingMax = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        vm.idolIds = Array(selectedIdols)
                        vm.tagIds = Array(selectedTags)
                        vm.studioId = selectedStudio
                        vm.seriesId = selectedSeries
                        vm.prefix = selectedPrefix
                        vm.solo = solo
                        vm.favoriteGroupId = favoriteGroupId
                        vm.ratingMin = Double(ratingMin)
                        vm.ratingMax = Double(ratingMax)
                        Task { await vm.refresh() }
                        dismiss()
                    }
                }
            }
            .task {
                await options.load(vm: vm)
                favoriteGroups = (try? await Repository(api: AppState.shared.api).listFavoriteGroups(.jav)) ?? []
                solo = vm.solo
                selectedIdols = Set(vm.idolIds)
                selectedTags = Set(vm.tagIds)
                selectedStudio = vm.studioId
                selectedSeries = vm.seriesId
                selectedPrefix = vm.prefix
                favoriteGroupId = vm.favoriteGroupId
                ratingMin = vm.ratingMin.map { String($0) } ?? ""
                ratingMax = vm.ratingMax.map { String($0) } ?? ""
            }
            .errorAlert(options.errorMessage) { options.errorMessage = nil }
        }
        .presentationDetents([.large])
    }
}

// MARK: - 女优筛选（三维范围）

struct IdolFilterSheet: View {
    @ObservedObject var vm: IdolsListVM
    @Environment(\.dismiss) private var dismiss

    @State private var heightMin = ""
    @State private var heightMax = ""
    @State private var ageMin = ""
    @State private var ageMax = ""
    @State private var cupMin = ""
    @State private var cupMax = ""
    @State private var bustMin = ""
    @State private var bustMax = ""
    @State private var waistMin = ""
    @State private var waistMax = ""
    @State private var hipsMin = ""
    @State private var hipsMax = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("身高（130-190cm）") {
                    HStack {
                        TextField("最低", text: $heightMin).keyboardType(.numberPad)
                        Text("~")
                        TextField("最高", text: $heightMax).keyboardType(.numberPad)
                    }
                }
                Section("年龄（18-60）") {
                    HStack {
                        TextField("最低", text: $ageMin).keyboardType(.numberPad)
                        Text("~")
                        TextField("最高", text: $ageMax).keyboardType(.numberPad)
                    }
                }
                Section("罩杯（1-11）") {
                    HStack {
                        TextField("最低", text: $cupMin).keyboardType(.numberPad)
                        Text("~")
                        TextField("最高", text: $cupMax).keyboardType(.numberPad)
                    }
                }
                Section("胸围（60-130）") {
                    HStack {
                        TextField("最低", text: $bustMin).keyboardType(.numberPad)
                        Text("~")
                        TextField("最高", text: $bustMax).keyboardType(.numberPad)
                    }
                }
                Section("腰围（45-100）") {
                    HStack {
                        TextField("最低", text: $waistMin).keyboardType(.numberPad)
                        Text("~")
                        TextField("最高", text: $waistMax).keyboardType(.numberPad)
                    }
                }
                Section("臀围（65-130）") {
                    HStack {
                        TextField("最低", text: $hipsMin).keyboardType(.numberPad)
                        Text("~")
                        TextField("最高", text: $hipsMax).keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("女优筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        vm.ranges = [
                            "idol_height": (Int(heightMin), Int(heightMax)),
                            "idol_age": (Int(ageMin), Int(ageMax)),
                            "idol_cup": (Int(cupMin), Int(cupMax)),
                            "idol_bust": (Int(bustMin), Int(bustMax)),
                            "idol_waist": (Int(waistMin), Int(waistMax)),
                            "idol_hips": (Int(hipsMin), Int(hipsMax)),
                        ]
                        Task { await vm.refresh() }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
