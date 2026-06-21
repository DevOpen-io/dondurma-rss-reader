import WidgetKit
import SwiftUI

// MARK: - Shared Types

private let appGroupId = "group.io.devopen.dondurma"

private struct ArticleEntry: Identifiable {
    let id = UUID()
    let title: String
    let siteName: String
    let timeAgo: String
}

private func loadArticles(key: String) -> [ArticleEntry] {
    guard
        let defaults = UserDefaults(suiteName: appGroupId),
        let json = defaults.string(forKey: key),
        let data = json.data(using: .utf8),
        let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
    else { return [] }

    return arr.map {
        ArticleEntry(
            title: $0["title"] ?? "",
            siteName: $0["siteName"] ?? "",
            timeAgo: $0["timeAgo"] ?? ""
        )
    }
}

private func loadCategory() -> (name: String, articles: [ArticleEntry]) {
    guard
        let defaults = UserDefaults(suiteName: appGroupId),
        let json = defaults.string(forKey: "widget_category"),
        let data = json.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let name = obj["name"] as? String,
        let arr = obj["articles"] as? [[String: String]]
    else { return ("Kategori", []) }

    let articles = arr.map {
        ArticleEntry(title: $0["title"] ?? "", siteName: $0["siteName"] ?? "", timeAgo: $0["timeAgo"] ?? "")
    }
    return (name, articles)
}

// MARK: - Shared Views

private struct WidgetHeader: View {
    let title: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "12A8FF"))
                .frame(width: 4, height: 16)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "12A8FF").opacity(0.6))
            }
        }
    }
}

private struct ArticleRow: View {
    let article: ArticleEntry

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: "12A8FF").opacity(0.4))
                .frame(width: 4, height: 4)
            Text(article.title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !article.timeAgo.isEmpty {
                Text(article.timeAgo)
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "12A8FF").opacity(0.55))
            }
        }
    }
}

private struct ArticleListBody: View {
    let articles: [ArticleEntry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(articles.enumerated()), id: \.offset) { idx, article in
                if idx > 0 {
                    Divider().background(Color.white.opacity(0.1)).padding(.vertical, 3)
                }
                ArticleRow(article: article)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct WidgetBackground: View {
    var body: some View {
        Color(hex: "131325").opacity(0.93)
    }
}

// MARK: - Latest News Widget

struct LatestNewsEntry: TimelineEntry {
    let date: Date
    let articles: [ArticleEntry]
}

struct LatestNewsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestNewsEntry {
        LatestNewsEntry(date: .now, articles: [
            ArticleEntry(title: "Breaking: Flutter 4 released with new features", siteName: "Flutter Blog", timeAgo: "2m"),
            ArticleEntry(title: "SwiftUI gets major performance improvements", siteName: "Apple Dev", timeAgo: "15m"),
            ArticleEntry(title: "Kotlin Multiplatform reaches stable milestone", siteName: "JetBrains", timeAgo: "1h"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestNewsEntry) -> Void) {
        completion(LatestNewsEntry(date: .now, articles: loadArticles(key: "widget_latest")))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestNewsEntry>) -> Void) {
        let entry = LatestNewsEntry(date: .now, articles: loadArticles(key: "widget_latest"))
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct LatestNewsWidget: Widget {
    let kind = "LatestNewsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestNewsProvider()) { entry in
            LatestNewsWidgetView(entry: entry)
                .containerBackground(WidgetBackground(), for: .widget)
        }
        .configurationDisplayName("Son Eklenenler")
        .description("En yeni haberleri ana ekranınızda görün.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct LatestNewsWidgetView: View {
    let entry: LatestNewsEntry
    @Environment(\.widgetFamily) var family

    var visibleCount: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 6
        case .systemExtraLarge: return 12
        default: return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Son Eklenenler", badge: "\(entry.articles.count)")
                .padding(.bottom, 8)
            if entry.articles.isEmpty {
                Text("Henüz haber yok")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ArticleListBody(articles: Array(entry.articles.prefix(visibleCount)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Category Widget

struct CategoryEntry: TimelineEntry {
    let date: Date
    let name: String
    let articles: [ArticleEntry]
}

struct CategoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> CategoryEntry {
        CategoryEntry(date: .now, name: "Teknoloji", articles: [
            ArticleEntry(title: "Flutter 4 duyuruldu", siteName: "Flutter", timeAgo: "5m"),
            ArticleEntry(title: "iOS 19 beta çıktı", siteName: "Apple", timeAgo: "1h"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (CategoryEntry) -> Void) {
        let (name, articles) = loadCategory()
        completion(CategoryEntry(date: .now, name: name, articles: articles))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CategoryEntry>) -> Void) {
        let (name, articles) = loadCategory()
        let entry = CategoryEntry(date: .now, name: name, articles: articles)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct CategoryWidget: Widget {
    let kind = "CategoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CategoryProvider()) { entry in
            CategoryWidgetView(entry: entry)
                .containerBackground(WidgetBackground(), for: .widget)
        }
        .configurationDisplayName("Kategoriye Özel")
        .description("En popüler kategorinizdeki haberleri görün.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct CategoryWidgetView: View {
    let entry: CategoryEntry
    @Environment(\.widgetFamily) var family

    var visibleCount: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 6
        case .systemExtraLarge: return 12
        default: return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: entry.name, badge: "\(entry.articles.count)")
                .padding(.bottom, 8)
            if entry.articles.isEmpty {
                Text("Bu kategoride haber yok")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ArticleListBody(articles: Array(entry.articles.prefix(visibleCount)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget Bundle

@main
struct DondurmaWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestNewsWidget()
        CategoryWidget()
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
