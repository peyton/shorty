import ShortyCore
import SwiftUI

/// Coverage dashboard showing installed apps and their adapter status (#2, #27).
struct AppCoverageView: View {
    let results: [AppScanResult]?
    let onGenerate: (String) -> Void
    let onScan: () -> Void

    @State private var searchText = ""
    @State private var filter: CoverageFilter = .all

    enum CoverageFilter: String, CaseIterable {
        case all = "All"
        case covered = "Covered"
        case uncovered = "Uncovered"
    }

    private var filteredResults: [AppScanResult] {
        guard let results else { return [] }
        return results.filter { result in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .covered:
                matchesFilter = result.hasCoverage
            case .uncovered:
                matchesFilter = !result.hasCoverage
            }
            let matchesSearch = searchText.isEmpty
                || result.appName.localizedCaseInsensitiveContains(searchText)
                || result.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let results {
                let summary = AppScanner.scanSummary(results: results)
                ShortyPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("App Coverage")
                                .font(.headline)
                            Spacer()
                            Button("Rescan", action: onScan)
                                .controlSize(.small)
                        }

                        CoverageBar(summary: summary)

                        Text(summary.summaryText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    TextField("Search apps...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("Filter", selection: $filter) {
                        ForEach(CoverageFilter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                }

                List(filteredResults) { result in
                    AppCoverageRow(result: result, onGenerate: onGenerate)
                }
            } else {
                ShortyPanel {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Scan your installed apps to see which ones have keyboard shortcuts.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Scan My Apps", action: onScan)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct CoverageBar: View {
    let summary: ScanSummary

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                if summary.totalApps > 0 {
                    Rectangle()
                        .fill(ShortyBrand.teal)
                        .frame(width: geo.size.width * CGFloat(summary.builtInCount) / CGFloat(summary.totalApps))
                    Rectangle()
                        .fill(ShortyBrand.teal.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(summary.generatedCount + summary.userDefinedCount) / CGFloat(summary.totalApps))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 8)
        .accessibilityLabel("\(summary.coveragePercentage)% app coverage")
    }
}

private struct AppCoverageRow: View {
    let result: AppScanResult
    let onGenerate: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let icon = result.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 24, height: 24)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.appName)
                    .font(.callout)
                    .lineLimit(1)
                Text(result.bundleIdentifier)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if result.hasCoverage {
                HStack(spacing: 4) {
                    Text(result.sourceLabel)
                        .font(.caption.weight(.semibold))
                    Text("(\(result.mappingCount))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(ShortyBrand.teal)
            } else {
                Button("Generate") {
                    onGenerate(result.bundleIdentifier)
                }
                .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.appName), \(result.hasCoverage ? "\(result.mappingCount) shortcuts" : "no coverage")")
    }
}
