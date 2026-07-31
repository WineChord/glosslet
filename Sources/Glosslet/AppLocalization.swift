import Foundation

enum AppLanguage {
    static var isSimplifiedChinese: Bool {
        let language = Locale.preferredLanguages.first?.lowercased() ?? ""
        return language.hasPrefix("zh-hans")
            || language.hasPrefix("zh-cn")
            || language.hasPrefix("zh-sg")
    }
}

enum L10n {
    static func text(_ english: String, _ simplifiedChinese: String) -> String {
        AppLanguage.isSimplifiedChinese ? simplifiedChinese : english
    }

    static let explain = text("Explain", "解释")
    static let copy = text("Copy", "复制")
    static let copyCode = text("Copy", "复制代码")
    static let copied = text("Copied", "已复制")
    static let image = text("Image", "图片")
    static let close = text("Close", "关闭")
    static let saved = text("Saved in Codex", "已存入 Codex")
    static let pinWindow = text(
        "Pin above other apps",
        "固定在其他应用上方"
    )
    static let unpinWindow = text(
        "Unpin and hide when focus moves away",
        "取消固定，失焦后自动隐藏"
    )
    static let showConversation = text(
        "Show current conversation",
        "显示当前对话"
    )
    static let settings = text("Settings…", "设置…")
    static let quit = text("Quit Glosslet", "退出 Glosslet")
    static let pause = text("Pause selection toolbar", "暂停划词工具条")
    static let resume = text("Enable selection toolbar", "启用划词工具条")
    static let onboardingTitle = text(
        "Explain anything, right where you read it.",
        "在阅读的地方，解释任何内容。"
    )
    static let accessibilityTitle = text(
        "Allow Accessibility access",
        "允许辅助功能权限"
    )
    static let accessibilityBody = text(
        "Glosslet reads only your current text selection so it can place the toolbar beside it. Text is sent to Codex only after you choose Explain.",
        "Glosslet 只读取你当前选中的文本，以便在旁边显示工具条。只有点击“解释”后，文本才会发送给 Codex。"
    )
    static let grantAccess = text(
        "Open Accessibility Settings",
        "打开辅助功能设置"
    )
    static let accessGranted = text("Access granted", "权限已授予")
    static let accessibilityRepairHint = text(
        "Already enabled after an update? Turn Glosslet off and on again. If it is still not recognized, remove the old entry and add the current app.",
        "更新后开关已经开启但仍未识别？请先关闭再重新开启 Glosslet；如果仍无效，请移除旧条目后重新添加当前应用。"
    )
    static let getStarted = text("Start using Glosslet", "开始使用 Glosslet")
    static let selectedFrom = text("Selected from", "选自")
    static let askFollowUp = text("Ask a follow-up…", "继续追问…")
    static let returnHint = text(
        "↵ Send · ⇧↵ New line",
        "↵ 发送 · ⇧↵ 换行"
    )
    static let send = text("Send", "发送")
    static let stop = text("Stop", "停止")
    static let newTask = text("New Codex task", "新建 Codex 任务")
    static let openCodex = text("Open Codex", "打开 Codex")
    static let taskSaved = text(
        "Saved in Codex",
        "已保存到 Codex"
    )
    static let connecting = text("Connecting to Codex…", "正在连接 Codex…")
    static let preparingTask = text("Preparing task…", "正在准备任务…")
    static let restoringTask = text(
        "Refreshing Codex task…",
        "正在刷新 Codex 任务…"
    )
    static let thinking = text("Codex is thinking…", "Codex 正在思考…")
    static let writingResponse = text(
        "Codex is writing…",
        "Codex 正在组织回复…"
    )
    static let elapsedSecondsSuffix = text("s", " 秒")
    static let stopped = text("Stopped", "已停止")
    static let done = text("Done", "已完成")
    static let approval = text("Codex needs approval", "Codex 需要授权")
    static let allowOnce = text("Allow once", "允许一次")
    static let allowSession = text("Allow for task", "本任务内允许")
    static let deny = text("Deny", "拒绝")
    static let general = text("General", "通用")
    static let codex = "Codex"
    static let about = text("About", "关于")
    static let selectionToolbar = text("Selection toolbar", "划词工具条")
    static let launchAtLogin = text("Launch at login", "登录时启动")
    static let conversationMode = text("Conversation mode", "会话模式")
    static let reuseTask = text(
        "Reuse one fixed Codex task",
        "复用一个固定 Codex 任务"
    )
    static let newForEach = text(
        "Create a task for every explanation",
        "每次解释新建一个任务"
    )
    static let modelMode = text("Model", "模型")
    static let chooseModel = text("Choose model", "选择模型")
    static let reasoning = text("Reasoning", "推理强度")
    static let chooseReasoning = text(
        "Choose reasoning effort",
        "选择推理强度"
    )
    static let latestLowest = text(
        "Latest model · lowest reasoning",
        "最新模型 · 最低推理"
    )
    static let codexDefaults = text(
        "Use Codex defaults",
        "沿用 Codex 默认设置"
    )
    static let custom = text("Custom", "自定义")
    static let responseLanguage = text("Response language", "回复语言")
    static let automatic = text("Automatic", "自动")
    static let systemLanguage = text("System language", "系统语言")
    static let simplifiedChinese = text("Simplified Chinese", "简体中文")
    static let english = text("English", "英语")
    static let fixedTask = text("Fixed Codex task", "固定 Codex 任务")
    static let noTaskYet = text(
        "Created after your first explanation",
        "将在第一次解释后创建"
    )
    static let resetTask = text("Start a new fixed task", "更换固定任务")
    static let privacyNote = text(
        "Copy stays local. Explain sends only the selected text and follow-ups through your installed Codex, using your Codex account and configuration.",
        "“复制”始终在本机完成。“解释”只会通过已安装的 Codex 发送选中文本与后续追问，并沿用你的 Codex 账户和配置。"
    )
    static let unofficial = text(
        "Glosslet is an open-source, unofficial companion for Codex.",
        "Glosslet 是一个开源、非官方的 Codex 辅助工具。"
    )

    static func completedIn(_ duration: TimeInterval) -> String {
        let seconds = max(1, Int(duration.rounded()))
        return text(
            "Done · \(seconds)s",
            "已完成 · \(seconds) 秒"
        )
    }

    static func failedIn(_ duration: TimeInterval) -> String {
        let seconds = max(1, Int(duration.rounded()))
        return text(
            "Couldn’t complete · \(seconds)s",
            "未能完成 · \(seconds) 秒"
        )
    }

    static func reasoningLabel(_ effort: String) -> String {
        switch effort {
        case "none":
            return text("None", "无")
        case "minimal":
            return text("Minimal", "最小")
        case "low":
            return text("Low", "低")
        case "medium":
            return text("Medium", "中")
        case "high":
            return text("High", "高")
        case "xhigh":
            return text("Extra high", "超高")
        case "max":
            return text("Maximum", "最大")
        case "ultra":
            return text("Ultra", "极高")
        default:
            return effort.capitalized
        }
    }

    static func reasoningDescription(
        _ effort: String,
        fallback: String
    ) -> String {
        guard AppLanguage.isSimplifiedChinese else {
            return fallback
        }
        switch effort {
        case "none":
            return "不进行额外推理"
        case "minimal":
            return "最短思考时间"
        case "low":
            return "轻量推理，响应更快"
        case "medium":
            return "速度与思考深度平衡"
        case "high":
            return "更深入地分析问题"
        case "xhigh":
            return "更充分的深度推理"
        case "max", "ultra":
            return "使用最高可用推理强度"
        default:
            return fallback
        }
    }
}
