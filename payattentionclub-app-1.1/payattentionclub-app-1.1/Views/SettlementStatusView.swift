import SwiftUI

struct SettlementStatusView: View {
    let status: WeekStatusResponse?
    let isLoading: Bool
    let errorMessage: String?
    var onRefresh: (() -> Void)? = nil
    
    private var summary: SettlementSummary? {
        guard let status else { return nil }
        return SettlementSummary(response: status)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider().opacity(0.2)
            content
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
    
    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly settlement")
                    .font(.headline)
                Text("Sync before Tuesday noon ET to stay on actual penalties.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                onRefresh?()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
            }
            .disabled(isLoading)
            .buttonStyle(.borderless)
            .accessibilityLabel("Refresh settlement status")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("Updating...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load status")
                    .font(.subheadline)
                    .foregroundColor(.red)
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button("Try again") {
                    onRefresh?()
                }
                .font(.footnote.weight(.semibold))
            }
        } else if let summary {
            statusRow(for: summary)
            if let weekDeadline = summary.formattedWeekDeadline {
                InfoRow(label: "Week deadline", value: weekDeadline)
            }
            if let graceDeadline = summary.formattedGraceDeadline {
                InfoRow(label: "Grace deadline", value: graceDeadline)
            }
            InfoRow(label: "Charged", value: currency(summary.chargedAmount))
            InfoRow(label: "Actual penalty", value: currency(summary.actualAmount))
            if summary.maxPenalty > 0 {
                InfoRow(label: "Max penalty", value: currency(summary.maxPenalty))
            }
            if summary.deltaAmount != 0 {
                let accent: Color = summary.deltaAmount < 0 ? .green : .orange
                InfoRow(
                    label: summary.deltaAmount < 0 ? "Refund delta" : "Extra charge",
                    value: currency(abs(summary.deltaAmount)),
                    accent: accent
                )
            }
        } else {
            Text("Open the app on Monday and Tuesday so we can sync your usage before the Tuesday noon ET settlement. If you skip the sync we charge the maximum." )
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    @ViewBuilder
    private func statusRow(for summary: SettlementSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary.statusIconName)
                .font(.title3.weight(.semibold))
                .foregroundColor(summary.badgeColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.badgeLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(summary.badgeColor)
                Text(summary.message)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(summary.badgeColor.opacity(0.08))
        .cornerRadius(12)
    }
    
    private func currency(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var accent: Color? = nil
    
    var body: some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundColor(accent ?? .primary)
        }
    }
}

private struct SettlementSummary {
    enum State {
        case waiting
        case chargedWorstCase
        case settledActual
        case refundPending
        // Note: adjustmentPending removed - late syncs can only result in refunds, never extra charges
    }
    
    let state: State
    let graceDeadline: Date?
    let weekDeadline: Date?
    let chargedAmount: Double
    let actualAmount: Double
    let maxPenalty: Double
    let deltaAmount: Double
    let message: String
    
    init(response: WeekStatusResponse) {
        chargedAmount = Double(response.chargedAmountCents) / 100.0
        let actual = response.actualAmountCents != 0 ? response.actualAmountCents : response.userTotalPenaltyCents
        actualAmount = Double(actual) / 100.0
        deltaAmount = Double(response.reconciliationDeltaCents) / 100.0
        graceDeadline = SettlementSummary.parse(dateString: response.weekGraceExpiresAt)
        weekDeadline = SettlementSummary.parse(dateString: response.weekEndDate)
        maxPenalty = Double(response.userMaxChargeCents) / 100.0
        
        let normalized = response.userSettlementStatus.lowercased()
        if response.needsReconciliation, response.reconciliationDeltaCents < 0 {
            state = .refundPending
            message = "Usage sync lowered your penalty. We'll send a refund for the difference as soon as Stripe settles."
        } else if response.needsReconciliation, response.reconciliationDeltaCents > 0 {
            // This should never happen for late syncs (validation prevents delta > 0)
            // But handle gracefully if it somehow occurs
            state = .refundPending
            message = "Reconciliation pending. Please contact support if you see this message."
        } else if normalized.contains("worst") {
            state = .chargedWorstCase
            message = "We charged the maximum because no sync arrived before Tuesday noon ET. You can still sync to trigger a refund."
        } else if normalized.contains("charged_actual") || normalized.contains("charged_actual_adjusted") || normalized.contains("settled") {
            state = .settledActual
            message = "You're settled for your actual usage. Thanks for syncing on time!"
        } else if normalized.contains("refunded") {
            state = .refundPending
            message = "A refund was issued after your late sync updated the numbers."
        } else {
            state = .waiting
            message = "Open the app before Tuesday noon ET so we can sync your usage and charge the actual amount instead of the worst case."
        }
    }
    
    var badgeLabel: String {
        switch state {
        case .waiting:
            return "Waiting for sync"
        case .chargedWorstCase:
            return "Charged worst-case"
        case .settledActual:
            return "Settled actual"
        case .refundPending:
            return "Refund pending"
        }
    }
    
    var badgeColor: Color {
        switch state {
        case .waiting:
            return .orange
        case .chargedWorstCase:
            return .red
        case .settledActual:
            return .green
        case .refundPending:
            return .blue
            return .purple
        }
    }
    
    var statusIconName: String {
        switch state {
        case .waiting:
            return "hourglass"
        case .chargedWorstCase:
            return "exclamationmark.triangle"
        case .settledActual:
            return "checkmark.seal"
        case .refundPending:
            return "arrow.triangle.2.circlepath"
            return "exclamationmark.arrow.triangle.2.circlepath"
        }
    }
    
    var formattedGraceDeadline: String? {
        guard let graceDeadline else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d · h:mm a 'ET'"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: graceDeadline)
    }
    
    var formattedWeekDeadline: String? {
        guard let weekDeadline else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d · h:mm a 'ET'"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: weekDeadline)
    }
    
    private static func parse(dateString: String?) -> Date? {
        guard let dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date
        }
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.timeZone = TimeZone(identifier: "America/New_York")
        return dateOnlyFormatter.date(from: dateString)
    }
}

#Preview("Waiting") {
    SettlementStatusView(
        status: WeekStatusResponse(
            userTotalPenaltyCents: 3200,
            userStatus: "pending",
            userMaxChargeCents: 4500,
            poolTotalPenaltyCents: 12000,
            poolStatus: "open",
            poolInstagramPostUrl: nil,
            poolInstagramImageUrl: nil,
            userSettlementStatus: "pending",
            chargedAmountCents: 0,
            actualAmountCents: 3200,
            refundAmountCents: 0,
            needsReconciliation: false,
            reconciliationDeltaCents: 0,
            reconciliationReason: nil,
            reconciliationDetectedAt: nil,
            weekGraceExpiresAt: "2025-12-02T17:00:00Z",
            weekEndDate: "2025-12-01"
        ),
        isLoading: false,
        errorMessage: nil,
        onRefresh: {}
    )
    .padding()
}
