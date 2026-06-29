import SwiftUI

struct IntegrationsListView: View {
    let hub: IntegrationHub

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Integrations")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(12)

            Divider()

            if hub.allConnectors().isEmpty {
                emptyState
            } else {
                List(hub.allConnectors(), id: \.id) { connector in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: icon(for: connector.id))
                            .font(.system(size: 14))
                            .foregroundStyle(.orbitPrimary)
                            .frame(width: 20)
                        Text(connector.name)
                            .font(.orbitBody)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orbitSuccess)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.orbitBackground)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "link")
                .font(.system(size: 32))
                .foregroundStyle(.orbitSecondary)
            Text("No Integrations")
                .font(.orbitBody)
                .foregroundStyle(.orbitSecondary)
            Text("Connect external services to extend Orbit's capabilities.")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func icon(for id: String) -> String {
        switch id {
        case "gmail": "envelope.fill"
        case "github": "chevron.left.forwardslash.chevron.right"
        case "slack": "message.fill"
        case "calendar": "calendar"
        case "notion": "note.text"
        case "drive": "folder.fill"
        default: "link"
        }
    }
}
