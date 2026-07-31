import Foundation

public enum ModelPolicy: String, CaseIterable, Sendable {
    case latestLowest
    case codexDefault
    case custom
}

public enum ModelSelection {
    private static let effortOrder = [
        "none",
        "minimal",
        "low",
        "medium",
        "high",
        "xhigh",
        "max",
        "ultra",
    ]

    public static func recommended(from models: [CodexModel]) -> ModelChoice {
        let visible = models.filter {
            !$0.hidden && $0.id != "codex-auto-review"
        }
        let selected =
            visible.first(where: \.isDefault)
            ?? visible.first(where: {
                $0.description.localizedCaseInsensitiveContains("latest")
            })
            ?? visible.first

        guard let selected else {
            return ModelChoice(
                model: nil,
                displayName: "Codex default",
                reasoningEffort: nil
            )
        }

        return ModelChoice(
            model: selected.model,
            displayName: selected.displayName,
            reasoningEffort: lowestEffort(
                in: selected.supportedReasoningEfforts
            ) ?? selected.defaultReasoningEffort,
            serviceTier: fastestServiceTier(in: selected)
        )
    }

    public static func resolve(
        policy: ModelPolicy,
        models: [CodexModel],
        customModelID: String?,
        customEffort: String?
    ) -> ModelChoice {
        switch policy {
        case .latestLowest:
            return recommended(from: models)
        case .codexDefault:
            return ModelChoice(
                model: nil,
                displayName: "Codex default",
                reasoningEffort: nil
            )
        case .custom:
            guard
                let selected = models.first(where: {
                    $0.id == customModelID || $0.model == customModelID
                })
            else {
                return recommended(from: models)
            }
            let supported = Set(
                selected.supportedReasoningEfforts.map(\.effort)
            )
            let effort =
                customEffort.flatMap {
                    supported.contains($0) ? $0 : nil
                } ?? selected.defaultReasoningEffort
            return ModelChoice(
                model: selected.model,
                displayName: selected.displayName,
                reasoningEffort: effort,
                serviceTier: fastestServiceTier(in: selected)
            )
        }
    }

    public static func lowestEffort(
        in options: [ReasoningEffortOption]
    ) -> String? {
        options.min { lhs, rhs in
            effortRank(lhs.effort) < effortRank(rhs.effort)
        }?.effort
    }

    public static func fastestServiceTier(in model: CodexModel) -> String? {
        if model.serviceTiers.contains(where: { $0.id == "priority" }) {
            return "priority"
        }
        if let defaultServiceTier = model.defaultServiceTier,
            model.serviceTiers.contains(where: {
                $0.id == defaultServiceTier
            })
        {
            return defaultServiceTier
        }
        return nil
    }

    private static func effortRank(_ effort: String) -> Int {
        effortOrder.firstIndex(of: effort) ?? (effortOrder.count + 1)
    }
}
