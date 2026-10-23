//! 播放尝试的失败分类与重试预算（词汇见根目录 `GLOSSARY.md`）。
//!
//! 一次播放尝试串联四个阶段：地址解析、签名、音频体传输、解密落盘。**只有串联它们
//! 的这一层知道失败发生在哪儿**，所以分类在这里产出，UI 只做翻译。
//!
//! S1 的已知上限：libresoda 把签名服务与元数据接口的网络失败都压成 `SodaError::Http(String)`
//! 这类**无相位**的变体，因此这里只能报到「地址解析（含签名）」这一粒度，
//! 「签名」要单列得等上游补结构化相位（见 `docs/adr/0001`）。

use libresoda::SodaError;
use std::fmt;
use std::time::Duration;

/// 失败发生的阶段。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage {
    /// 取回可用流及其地址，含向签名服务请求签名（S1 无法把两者分开）。
    ResolveStream,
    /// 把音频体的字节从 CDN 搬到本地。
    Transfer,
    /// 解密并落盘到缓存。
    Unpack,
    /// 调用方参数本身就不合法。
    Input,
}

/// 该失败能否自动重试。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Retryability {
    /// 网络抖动类，可以立刻再来一次。
    Transient,
    /// 被限流，可以重试但要等得更久。
    Throttled,
    /// 重试无意义：再打只是打扰签名服务和 CDN，不会变好。
    Never,
}

/// 失败绑定的用户侧修复动作。UI 用它选文案，不是靠解析错误字符串。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryAction {
    /// 无需用户做什么（等一会再试即可）。
    Nothing,
    /// 登录态问题，需要重新登录。
    Relogin,
    /// 签名服务不可用或鉴权失败，可在设置页换地址 / Token，或本机跑 libmssdk。
    CheckSigner,
    /// 当前账号对该曲目没有整曲权益。
    CheckEntitlement,
    /// 曲目已下架或取不到。
    PickAnother,
    /// 本地磁盘或文件写入问题。
    FreeSpace,
}

/// 一次播放尝试的失败：阶段 + 可否重试 + 修复动作 + 已脱敏的原始信息。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaybackFailure {
    pub stage: Stage,
    pub retryability: Retryability,
    pub action: RecoveryAction,
    /// 供日志与界面补充说明；**已经过 [`redact_url_secrets`] 脱敏**。
    pub detail: String,
}

impl PlaybackFailure {
    pub fn new(
        stage: Stage,
        retryability: Retryability,
        action: RecoveryAction,
        detail: impl Into<String>,
    ) -> Self {
        Self {
            stage,
            retryability,
            action,
            detail: redact_url_secrets(&detail.into()),
        }
    }
}

impl fmt::Display for PlaybackFailure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let stage = match self.stage {
            Stage::ResolveStream => "地址解析",
            Stage::Transfer => "音频体传输",
            Stage::Unpack => "解密落盘",
            Stage::Input => "参数",
        };
        write!(f, "{stage}失败：{}", self.detail)
    }
}

impl std::error::Error for PlaybackFailure {}

/// 把 `SodaError` 翻译成播放尝试的失败分类。
///
/// 判据来自 libresoda 实际的产出形态：签名服务的回包错误以 `signer error:` 开头、
/// 鉴权失败带「要求鉴权」，HTTP 状态错误是 `http request failed: status {code} (…)`，
/// 业务错误保留 `Api { status_code, .. }`。**未匹配的形态一律不重试**——
/// 「不默认重试」比「猜一次也许能好」更省那台共享签名服务。
pub fn classify(error: &SodaError) -> PlaybackFailure {
    let detail = error.to_string();

    if error.is_missing_entitlement() || error.is_cookie_required() {
        return PlaybackFailure::new(
            Stage::ResolveStream,
            Retryability::Never,
            RecoveryAction::CheckEntitlement,
            detail,
        );
    }

    // 签名服务的错误形态不止一种：`signer error:`（回包 ok:false）、`signer response decode`
    // （回包不是预期 JSON）、`signer spawn/stdin/wait`（本机签名器没跑起来）。共同点是我们对
    // 那台共享服务没有杠杆，所以一律不自动重试，并把出口指向设置页或本机 libmssdk。
    if detail.contains("signer") {
        return PlaybackFailure::new(
            Stage::ResolveStream,
            Retryability::Never,
            RecoveryAction::CheckSigner,
            detail,
        );
    }

    match error {
        SodaError::InvalidInput(_) => PlaybackFailure::new(
            Stage::Input,
            Retryability::Never,
            RecoveryAction::Nothing,
            detail,
        ),
        SodaError::NotFound(_) | SodaError::Unsupported(_) => PlaybackFailure::new(
            Stage::ResolveStream,
            Retryability::Never,
            RecoveryAction::PickAnother,
            detail,
        ),
        SodaError::Io(_) => PlaybackFailure::new(
            Stage::Unpack,
            Retryability::Never,
            RecoveryAction::FreeSpace,
            detail,
        ),
        SodaError::Crypto(_) => PlaybackFailure::new(
            Stage::Unpack,
            Retryability::Never,
            RecoveryAction::Nothing,
            detail,
        ),
        SodaError::Api { status_code, .. } => {
            // 汽水业务码：未登录一类要重新登录。业务码语义我们没实测过，
            // 所以一律不自动重试——猜错方向的代价是打爆接口，收益只是省一次重登。
            let action = matches!(*status_code, 7 | 401 | 403)
                .then_some(RecoveryAction::Relogin)
                .unwrap_or(RecoveryAction::Nothing);
            PlaybackFailure::new(Stage::ResolveStream, Retryability::Never, action, detail)
        }
        SodaError::Json(_) => PlaybackFailure::new(
            Stage::ResolveStream,
            Retryability::Transient,
            RecoveryAction::Nothing,
            detail,
        ),
        SodaError::Http(_) => classify_http(&detail),
    }
}

/// `SodaError::Http` 只剩字符串，相位信息已经在上游丢失；这里只解析结构化的状态码。
fn classify_http(detail: &str) -> PlaybackFailure {
    let status = detail
        .split("status ")
        .nth(1)
        .and_then(|rest| rest.chars().take(3).collect::<String>().parse::<u16>().ok());
    let (retryability, action) = match status {
        Some(429) => (Retryability::Throttled, RecoveryAction::Nothing),
        Some(401) => (Retryability::Never, RecoveryAction::Relogin),
        // 403 既可能是 Cookie 权益，也可能是签名 URL 过期：后者换一次地址就能好，
        // 所以按可重试处理，让它走一次「重新解析」而不是永久失败。
        Some(403) => (Retryability::Transient, RecoveryAction::Nothing),
        Some(404) => (Retryability::Never, RecoveryAction::PickAnother),
        Some(500..=599) => (Retryability::Transient, RecoveryAction::Nothing),
        Some(_) => (Retryability::Never, RecoveryAction::Nothing),
        None => {
            // 没有状态码的就是传输层：超时 / 连接重置 / DNS。
            if detail.contains("timed out") || detail.contains("timeout") {
                (Retryability::Transient, RecoveryAction::Nothing)
            } else {
                (Retryability::Never, RecoveryAction::Nothing)
            }
        }
    };
    let stage = if detail.contains("http request failed") {
        // 这个前缀是 `get_full` / `get_reader` 在**拿到状态码**时产出的；读体阶段一般不会有
        // 状态码（响应头已经过了），所以带前缀的归地址解析，纯传输层错误归音频体传输。
        Stage::ResolveStream
    } else {
        Stage::Transfer
    };
    PlaybackFailure::new(stage, retryability, action, detail)
}

/// 抹掉文本里任何 URL 的查询串：播放地址的 token 就在其中，绝不能进用户可见文案。
pub fn redact_url_secrets(text: &str) -> String {
    text.split_inclusive(char::is_whitespace)
        .map(|token| {
            let body = token.trim_end_matches(char::is_whitespace);
            let whitespace = &token[body.len()..];
            let cut = match body.find("://") {
                Some(_) => body.find('?'),
                None => None,
            };
            match cut {
                Some(at) => format!("{}?…{}", &body[..at], whitespace),
                None => token.to_string(),
            }
        })
        .collect()
}

/// 一次播放尝试的重试预算：**只有一层，且只按「这次失败值不值得再来一次」判**。
///
/// 不设总墙钟时长：那等于把刚从 libresoda 拆掉的「整首下载总时限」从另一侧装回来，
/// 慢但仍在推进的传输会被误杀。不设「无进展时长」也不是疏忽——S1 里根本没有可观测的
/// 进展信号：`download_to_cache` 是一次阻塞调用，失败即删掉 `.part`，跨尝试零进度。
/// 单次尝试内部的「卡住」由 libresoda 的空闲读超时（20s）负责；等阶段二有了
/// 密文暂存 + `Range` 续传，字节偏移才第一次成为可读的进度，那时才谈得上无进展封顶。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlayBudget {
    pub max_attempts: u8,
}

impl Default for PlayBudget {
    fn default() -> Self {
        Self { max_attempts: 3 }
    }
}

impl PlayBudget {
    /// 这次失败后要不要再来一次，以及该等多久。
    ///
    /// `attempt` 是**已经做完的尝试次数**；`jitter` 取 `[0,1)` 由调用方提供，
    /// 这样纯函数在单测里可复现（full jitter：`rand(0, min(cap, base × 2^n))`）。
    pub fn next_delay(
        &self,
        attempt: u8,
        failure: &PlaybackFailure,
        jitter: f32,
    ) -> Option<Duration> {
        if failure.retryability == Retryability::Never || attempt >= self.max_attempts {
            return None;
        }
        let base = match failure.retryability {
            Retryability::Throttled => Duration::from_secs(4),
            _ => Duration::from_secs(1),
        };
        let cap = Duration::from_secs(20);
        let ceiling = (base * 2u32.pow(attempt.saturating_sub(1).min(4) as u32)).min(cap);
        Some(ceiling.mul_f32(jitter.clamp(0.0, 0.999)))
    }
}

/// 取一个免依赖的抖动源：用「距离上一次有进展的时长」的纳秒尾数，
/// 每次失败的值都不同，足以把重试错开，又不用引入随机数依赖。
pub fn jitter_from_elapsed(since: Duration) -> f32 {
    (since.subsec_nanos() % 1000) as f32 / 1000.0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn failure(error: SodaError) -> PlaybackFailure {
        classify(&error)
    }

    #[test]
    fn permanent_shapes_are_never_retried_and_carry_an_action() {
        let cases = [
            (
                SodaError::http(
                    "signer error: bad token（签名服务要求鉴权：设置 QISHUI_SIGNER_TOKEN）",
                ),
                RecoveryAction::CheckSigner,
            ),
            // 回包不是预期 JSON 同样算签名服务故障：也不该自动重试。
            (
                SodaError::json("signer response decode: expected value at line 1 column 1"),
                RecoveryAction::CheckSigner,
            ),
            (
                SodaError::http("http request failed: status 404 (https://x.test/a)"),
                RecoveryAction::PickAnother,
            ),
            (SodaError::api(7, "need login"), RecoveryAction::Relogin),
            (SodaError::Io("disk full".into()), RecoveryAction::FreeSpace),
            (
                SodaError::not_found("track not found"),
                RecoveryAction::PickAnother,
            ),
            (
                SodaError::http("soda pc track_v2 returned preview stream"),
                RecoveryAction::CheckEntitlement,
            ),
            (
                SodaError::invalid_input("track id is empty"),
                RecoveryAction::Nothing,
            ),
        ];
        for (error, action) in cases {
            let classified = failure(error);
            assert_eq!(
                classified.retryability,
                Retryability::Never,
                "不该自动重试：{classified:?}"
            );
            assert_eq!(classified.action, action, "修复动作错位：{classified:?}");
        }
    }

    #[test]
    fn transient_shapes_stay_retriable() {
        // 传输层空闲读超时：没有状态码，落在音频体传输。
        let timeout = failure(SodaError::http("io: timed out reading response"));
        assert_eq!(timeout.retryability, Retryability::Transient);
        assert_eq!(timeout.stage, Stage::Transfer);

        // 签名 URL 过期：换一次地址就能好，按可重试处理。
        let forbidden = failure(SodaError::http(
            "http request failed: status 403 (https://cdn.test/p?token=abc)",
        ));
        assert_eq!(forbidden.retryability, Retryability::Transient);
        assert_eq!(forbidden.stage, Stage::ResolveStream);

        // 限流要等得更久。
        let throttled = failure(SodaError::http(
            "http request failed: status 429 (https://x)",
        ));
        assert_eq!(throttled.retryability, Retryability::Throttled);
    }

    #[test]
    fn unknown_shapes_default_to_no_retry() {
        // 「不默认重试」：认不出形态的 HTTP 错误不能变成盲试。
        let odd = failure(SodaError::http("connection reset by peer on a socket"));
        assert_eq!(odd.retryability, Retryability::Never);
    }

    #[test]
    fn redact_keeps_host_and_drops_signed_query() {
        let text =
            "http request failed: status 403 (https://v26-luna.test/asset/m4a?rid=1&sign=SECRET)";
        let redacted = redact_url_secrets(text);
        assert!(
            redacted.contains("https://v26-luna.test/asset/m4a?…"),
            "{redacted}"
        );
        assert!(!redacted.contains("SECRET"), "{redacted}");
        // 不带 ? 的 URL 与普通问号都不该被动到。
        assert_eq!(
            redact_url_secrets("是不是失败了? 再试吗"),
            "是不是失败了? 再试吗"
        );
        // 分类结果里存的一定是脱敏后的文本。
        let failure = failure(SodaError::http(text));
        assert!(!failure.detail.contains("SECRET"), "{}", failure.detail);
    }

    #[test]
    fn budget_gates_on_retryability_and_attempts() {
        let budget = PlayBudget::default();
        let transient = PlaybackFailure::new(
            Stage::Transfer,
            Retryability::Transient,
            RecoveryAction::Nothing,
            "io: timed out reading response",
        );
        let permanent = PlaybackFailure::new(
            Stage::ResolveStream,
            Retryability::Never,
            RecoveryAction::Relogin,
            "signer error",
        );

        // 永久错误一次都不重试：再打只是打扰那台共享签名服务。
        assert_eq!(budget.next_delay(1, &permanent, 0.5), None);
        assert!(budget.next_delay(1, &transient, 0.5).is_some());
        // 次数封顶是唯一的上限（S1 没有可观测的字节进度，见 PlayBudget 文档）。
        assert_eq!(budget.next_delay(3, &transient, 0.5), None);
        // full jitter：等待时长受抖动系数缩放，且不超过上限。
        let ceiling = budget.next_delay(1, &transient, 0.999).unwrap();
        let floor = budget.next_delay(1, &transient, 0.0).unwrap();
        assert!(floor < ceiling, "{floor:?} {ceiling:?}");
        assert!(ceiling <= Duration::from_secs(20), "{ceiling:?}");
        // 限流基数比瞬时更长。
        let throttled = PlaybackFailure::new(
            Stage::ResolveStream,
            Retryability::Throttled,
            RecoveryAction::Nothing,
            "429",
        );
        assert!(budget.next_delay(1, &throttled, 0.9) > budget.next_delay(1, &transient, 0.9));
    }

    #[test]
    fn default_budget_allows_three_attempts() {
        assert_eq!(PlayBudget::default().max_attempts, 3);
    }

    #[test]
    fn every_variant_classifies_without_panicking() {
        let variants = [
            SodaError::http("x"),
            SodaError::json("x"),
            SodaError::api(1, "x"),
            SodaError::crypto("x"),
            SodaError::unsupported("x"),
            SodaError::invalid_input("x"),
            SodaError::not_found("x"),
            SodaError::Io("x".into()),
        ];
        for error in variants {
            let _ = classify(&error);
        }
    }
}
