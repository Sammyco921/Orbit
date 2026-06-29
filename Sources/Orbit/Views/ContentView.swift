import SwiftUI

public struct ContentView: View {
    @Environment(Orchestrator.self) private var orchestrator

    public init() {}

    public var body: some View {
        AppShellView()
            .environment(orchestrator)
    }
}
