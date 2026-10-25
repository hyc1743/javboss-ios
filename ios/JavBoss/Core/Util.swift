import SwiftUI

// MARK: - 格式化

enum Fmt {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func duration(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "--:--" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func ms(_ value: Int64) -> String {
        duration(value / 1000)
    }

    /// RFC3339 或常见格式日期字符串 → yyyy-MM-dd
    static func date(_ raw: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return "-" }
        let cleaned = raw.replacingOccurrences(of: "Z", with: "+00:00")
        let trimmed = cleaned.prefix(10)
        return String(trimmed)
    }

    static func dateTime(_ raw: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return "-" }
        if let date = parseISO(raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
        return String(raw.prefix(16))
    }

    static func parseISO(_ raw: String) -> Date? {
        let cleaned = raw.replacingOccurrences(of: "Z", with: "+00:00")
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: cleaned) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: cleaned)
    }

    static func count(_ value: Int64?) -> String {
        guard let value else { return "0" }
        return value >= 10000 ? String(format: "%.1f万", Double(value) / 10000) : String(value)
    }
}

// MARK: - 通用错误提示

struct ErrorAlertModifier: ViewModifier {
    let message: String?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.alert("提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { onDismiss() } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func errorAlert(_ message: String?, onDismiss: @escaping () -> Void) -> some View {
        modifier(ErrorAlertModifier(message: message, onDismiss: onDismiss))
    }
}

// MARK: - 分页列表 ViewModel 基类

@MainActor
class PagedListVM<T: Identifiable>: ObservableObject {
    @Published var items: [T] = []
    @Published var total = 0
    @Published var loading = false
    @Published var loadingMore = false
    @Published var errorMessage: String?

    var pageSize = 50
    private var isLoading = false

    func clearError() { errorMessage = nil }

    func refresh() async {
        await load(reset: true)
    }

    func loadMoreIfNeeded(current item: T) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              index >= items.count - 8 else { return }
        if items.count < total || total == 0 {
            await load(reset: false)
        }
    }

    /// 子类实现：返回 (items, total)
    func fetchPage(offset: Int) async throws -> ([T], Int) {
        ([], 0)
    }

    func load(reset: Bool) async {
        if isLoading { return }
        isLoading = true
        if reset {
            loading = true
        } else {
            loadingMore = true
        }
        let offset = reset ? 0 : items.count
        do {
            let (page, total) = try await fetchPage(offset: offset)
            if reset {
                items = page
                self.total = total
            } else {
                items.append(contentsOf: page)
                self.total = total
            }
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
        loadingMore = false
        isLoading = false
    }
}

// MARK: - 标签流式布局

struct ChipFlowLayout: View {
    let chips: [String]
    var selected: Set<String> = []
    var onTap: ((String) -> Void)?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 76), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(selected.contains(chip) ? Color.orange.opacity(0.35) : Color(white: 0.22))
                    )
                    .foregroundStyle(selected.contains(chip) ? .orange : .primary)
                    .onTapGesture {
                        onTap?(chip)
                    }
            }
        }
    }
}

// MARK: - 搜索栏

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                    onSubmit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 空状态 / 加载

struct EmptyPlaceholder: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 确认对话框

struct ConfirmDialogModifier: ViewModifier {
    let title: String
    let message: String
    let confirmLabel: String
    @Binding var isPresented: Bool
    let destructive: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button(confirmLabel, role: destructive ? .destructive : nil, action: action)
            Button("取消", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

extension View {
    func confirmDialog(title: String, message: String, confirmLabel: String = "确定",
                       destructive: Bool = false, isPresented: Binding<Bool>,
                       action: @escaping () -> Void) -> some View {
        modifier(ConfirmDialogModifier(title: title, message: message, confirmLabel: confirmLabel,
                                       isPresented: isPresented, destructive: destructive, action: action))
    }
}

// MARK: - 文本输入对话框

struct TextInputDialog: View {
    let title: String
    let placeholder: String
    let initial: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { submit() }
            HStack {
                Button("取消", role: .cancel, action: onCancel)
                    .frame(maxWidth: .infinity)
                Button("确定", action: submit)
                    .frame(maxWidth: .infinity)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 40)
        .onAppear { text = initial }
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespaces)
        if !value.isEmpty { onSubmit(value) }
    }
}
