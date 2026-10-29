import Foundation
import AgentMeterCore
@main struct CLI {
    static func main() async {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if CommandLine.arguments.dropFirst().first == "system" {
                let sampler = SystemSampler(); _ = sampler.sample(); try await Task.sleep(for: .seconds(1))
                print(String(decoding: try encoder.encode(sampler.sample()), as: UTF8.self)); return
            }
            guard let name = CommandLine.arguments.dropFirst().first, let provider = Provider(rawValue: name) else { print("agentmeter-cli system | codex | claude"); return }
            let value = try await DirectQuotaService().fetch(provider: provider, allowKeychainPrompt: CommandLine.arguments.contains("--allow-keychain-prompt"))
            print(String(decoding: try encoder.encode(value), as: UTF8.self))
        } catch { let value = (error as? QuotaError) ?? .unavailable; print("\(value.rawValue): \(value.message)"); exit(1) }
    }
}
