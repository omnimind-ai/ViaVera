import Foundation

nonisolated enum ModelVendorCatalog {
    static func assetName(for model: ModelOption?, provider: ProviderProfile?) -> String? {
        match(for: model, provider: provider)?.assetName
    }

    static func usesTemplateRendering(
        for model: ModelOption?,
        provider: ProviderProfile?
    ) -> Bool {
        match(for: model, provider: provider)?.isMonochrome ?? true
    }

    static func symbolName(for model: ModelOption?, provider: ProviderProfile?) -> String {
        match(for: model, provider: provider)?.symbol ?? "sparkles"
    }

    private static func match(
        for model: ModelOption?,
        provider: ProviderProfile?
    ) -> (
        aliases: [String],
        assetName: String,
        symbol: String,
        isMonochrome: Bool
    )? {
        let values = [
            model?.id,
            model?.providerName,
            model?.modelsDevProviderID,
            provider?.name,
        ]
        .compactMap { $0?.lowercased() }

        for value in values {
            if let match = catalog.first(where: { vendor in
                vendor.aliases.contains(where: value.contains)
            }) {
                return match
            }
        }
        return nil
    }

    private static let catalog: [(
        aliases: [String],
        assetName: String,
        symbol: String,
        isMonochrome: Bool
    )] = [
        (["openai", "chatgpt", "gpt", "codex", "o1", "o3", "o4"], "ProviderVendorOpenAI", "circle.hexagongrid", true),
        (["anthropic", "claude"], "ProviderVendorAnthropic", "sun.max", true),
        (["google", "gemini", "gemma", "imagen", "veo", "nano-banana"], "ProviderVendorGoogle", "diamond", false),
        (["meta", "llama"], "ProviderVendorMeta", "infinity", false),
        (["microsoft", "azure", "phi"], "ProviderVendorMicrosoft", "square.grid.2x2", false),
        (["amazon", "aws", "bedrock", "nova", "titan"], "ProviderVendorAmazon", "shippingbox", true),
        (["nvidia", "nemotron"], "ProviderVendorNvidia", "memorychip", false),
        (["deepseek"], "ProviderVendorDeepSeek", "waveform.path.ecg", false),
        (["moonshot", "moonshotai", "kimi"], "ProviderVendorMoonshot", "moonphase.waxing.crescent", false),
        (["zhipu", "zhipuai", "glm", "chatglm", "bigmodel"], "ProviderVendorZhipu", "hexagon", false),
        (["minimax", "abab", "hailuo"], "ProviderVendorMiniMax", "waveform", false),
        (["bytedance", "doubao", "seed", "volcengine"], "ProviderVendorByteDance", "music.note", false),
        (["tencent", "hunyuan"], "ProviderVendorTencent", "cloud", false),
        (["longcat"], "ProviderVendorLongCat", "cat", true),
        (["mistral", "mixtral", "ministral", "magistral", "codestral", "devstral", "pixtral"], "ProviderVendorMistral", "wind", false),
        (["alibaba", "qwen", "qwq", "qvq", "dashscope", "tongyi", "wanx"], "ProviderVendorAlibaba", "cloud.fill", false),
        (["xai", "grok"], "ProviderVendorXAI", "xmark", true),
        (["xiaomi", "mimo", "xiaomimimo"], "ProviderVendorXiaomi", "house", true),
        (["iflytek", "iflytekcloud", "spark", "讯飞", "星火"], "ProviderVendorIFlytek", "waveform.and.mic", false),
        (["stepfun", "step", "阶跃星辰"], "ProviderVendorStepFun", "stairs", false),
        (["baichuan", "百川"], "ProviderVendorBaichuan", "water.waves", false),
        (["baidu", "ernie", "wenxin", "qianfan", "文心", "百度"], "ProviderVendorBaidu", "pawprint", false),
        (["cohere", "command", "aya"], "ProviderVendorCohere", "circle.grid.2x2", false),
        (["perplexity", "sonar", "pplx"], "ProviderVendorPerplexity", "magnifyingglass", false),
        (["01-ai", "01ai", "zeroone", "lingyiwanwu", "yi-", "零一万物"], "ProviderVendorYi", "1.circle", true),
        (["internlm", "internvl"], "ProviderVendorInternLM", "network", false),
        (["openrouter"], "ProviderVendorOpenRouter", "point.3.connected.trianglepath.dotted", true),
        (["copilot", "github"], "ProviderVendorCopilot", "chevron.left.forwardslash.chevron.right", false),
    ]
}
