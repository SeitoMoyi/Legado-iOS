import Foundation
#if canImport(LegadoCore)
import LegadoCore
#endif

public class SearchViewModel: ObservableObject {
    public static let shared = SearchViewModel()

    @Published public var searchQuery: String = ""
    @Published public var searchResults: [SearchBook] = []
    @Published public var isSearching: Bool = false
    @Published public var isLoadingMore: Bool = false
    @Published public var currentPage: Int = 1
    @Published public var hasMore: Bool = true
    /// Which sources to search. Persisted as Android's `searchScope` preference.
    @Published public var scope: SearchScope {
        didSet { persistScope() }
    }
    @Published public var precisionSearch: Bool {
        didSet { persistPrecision() }
    }
    /// True when the user pressed 停止; auto-paging must not resume on its own then.
    @Published public private(set) var isManuallyStopped: Bool = false

    private var exhaustedSourceUrls: Set<String> = []
    private var currentSearchTask: Task<Void, Never>? = nil
    /// Snapshot of the sources a running search covers, so changing the scope mid-flight
    /// cannot make the paging bookkeeping inconsistent.
    private var searchedSources: [BookSource] = []

    public init() {
        let prefs = ReaderStore.loadPrefs()
        scope = SearchScope(raw: prefs.searchScope)
        precisionSearch = prefs.precisionSearch
    }

    private func persistScope() {
        var prefs = ReaderStore.loadPrefs()
        prefs.searchScope = scope.raw
        prefs.searchGroup = scope.singleGroup
        // Keep the live copy in sync for whoever else reads preferences this session.
        ReaderStore.save(prefs)
        ReaderConfig.shared.prefs = prefs
    }

    private func persistPrecision() {
        var prefs = ReaderStore.loadPrefs()
        prefs.precisionSearch = precisionSearch
        ReaderStore.save(prefs)
        ReaderConfig.shared.prefs = prefs
    }

    public var availableSources: [BookSource] {
        BookStore.shared.sources.filter { $0.enabled != false && $0.searchUrl != nil }
    }

    /// Enabled sources inside the chosen scope. `availableSources` keeps the Android filter
    /// of "has a search url"; group scope narrows further.
    public var targetSources: [BookSource] {
        scope.resolve(in: availableSources).sources
    }

    /// A scope naming a deleted group or source collapses back to "all". Done from view
    /// lifecycle rather than `targetSources` because rewriting a @Published value during a
    /// body evaluation triggers "Publishing changes from within view updates".
    public func reconcileScope() {
        let resolved = scope.resolve(in: availableSources)
        if resolved.scope != scope { scope = resolved.scope }
    }

    /// Restricts the search to one source, using Android's "name::url" encoding.
    public func selectSource(url: String?) {
        guard let url, let source = availableSources.first(where: { $0.bookSourceUrl == url }) else {
            scope = .all
            return
        }
        scope = SearchScope(raw: "\(source.bookSourceName)::\(url)")
    }

    /// Display name of the single source the scope points at, if any.
    public var scopedSourceName: String? {
        guard let url = scope.sourceUrl else { return nil }
        return availableSources.first { $0.bookSourceUrl == url }?.bookSourceName
    }

    public func cancelAndReset() {
        currentSearchTask?.cancel()
        currentSearchTask = nil
        searchedSources = []
        isManuallyStopped = false
        searchResults.removeAll()
        exhaustedSourceUrls.removeAll()
        isSearching = false
        isLoadingMore = false
        currentPage = 1
        hasMore = true
    }

    public func startSearch() {
        let key = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        cancelAndReset()
        isSearching = true
        isManuallyStopped = false
        BookStore.shared.recordSearchKeyword(key)

        reconcileScope()
        let sources = targetSources
        guard !sources.isEmpty else {
            isSearching = false
            hasMore = false
            return
        }

        searchedSources = sources
        currentSearchTask = Task {
            let stream = BookSearchService.shared.searchMultiSources(sources: sources, key: key, page: 1)

            for await (source, books) in stream {
                if Task.isCancelled { return }

                await MainActor.run {
                    if books.isEmpty {
                        self.exhaustedSourceUrls.insert(source.bookSourceUrl)
                    } else {
                        self.appendDeduplicated(books)
                    }
                }
            }

            if Task.isCancelled { return }

            await MainActor.run {
                self.isSearching = false
                self.currentPage = 1
                if self.exhaustedSourceUrls.count >= sources.count || self.searchResults.isEmpty {
                    self.hasMore = false
                } else {
                    self.hasMore = true
                }
            }
        }
    }

    public func shouldAutoLoadMore(for item: SearchBook) -> Bool {
        guard !isSearching, !isLoadingMore, hasMore else { return false }
        guard let index = searchResults.firstIndex(where: { $0.id == item.id }) else { return false }
        return index >= searchResults.count - 3
    }

    public func loadNextPage() {
        guard !isSearching, !isLoadingMore, hasMore else { return }

        let key = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        guard !isManuallyStopped else { return }
        let sourcesToQuery = (searchedSources.isEmpty ? targetSources : searchedSources)
            .filter { !exhaustedSourceUrls.contains($0.bookSourceUrl) }
        guard !sourcesToQuery.isEmpty else {
            hasMore = false
            return
        }

        isLoadingMore = true
        let nextPage = currentPage + 1
        let countBeforeNextPage = searchResults.count

        currentSearchTask = Task {
            let stream = BookSearchService.shared.searchMultiSources(sources: sourcesToQuery, key: key, page: nextPage)

            for await (source, books) in stream {
                if Task.isCancelled { return }

                await MainActor.run {
                    if books.isEmpty {
                        self.exhaustedSourceUrls.insert(source.bookSourceUrl)
                    } else {
                        self.appendDeduplicated(books)
                    }
                }
            }

            if Task.isCancelled { return }

            await MainActor.run {
                self.isLoadingMore = false
                self.currentPage = nextPage
                let foundAny = self.searchResults.count > countBeforeNextPage
                let pool = self.searchedSources.isEmpty ? self.targetSources : self.searchedSources
                let remainingSources = pool.filter { !self.exhaustedSourceUrls.contains($0.bookSourceUrl) }
                if remainingSources.isEmpty || !foundAny {
                    self.hasMore = false
                }
            }
        }
    }

    /// Folds new hits in by (name, author) — so the same book found on five sources is one
    /// row with five origins — then re-ranks with the 精准/包含/其余 buckets Android uses.
    private func appendDeduplicated(_ newBooks: [SearchBook]) {
        let key = searchQuery.trimmingCharacters(in: .whitespaces)
        searchResults = SearchMerger.rank(SearchMerger.merge(searchResults, newBooks),
                                          key: key, precision: precisionSearch)
    }

    /// Android's `isManualStopSearch`: a stopped search keeps its results and can be resumed.
    public func stopSearch() {
        currentSearchTask?.cancel()
        currentSearchTask = nil
        isSearching = false
        isManuallyStopped = true
    }

    public func resumeSearch() {
        guard isManuallyStopped else { return }
        isManuallyStopped = false
        if searchResults.isEmpty { startSearch() } else { loadNextPage() }
    }
}
