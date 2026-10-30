//! 底部状态行：`Root::status_line` 的唯一渲染出口（#83）。
//!
//! 普通操作反馈（切档、开关、收藏、加载中…）有六十多处写入点。它们以前只写不画，
//! 用户看不到；这里给它们一个固定位置：播放栏上方左侧一行，停留 [`VISIBLE_FOR`]
//! 后自行消失。重要的、需要打断的事件仍然走 [`crate::ui::message`] 的全局轻提示，
//! 两条通道各管一件事——轻提示负责「叫住你」，状态行负责「留下来说过什么」。

use std::time::{Duration, Instant};

use gpui::prelude::*;
use gpui::{div, px, AnyElement, Context};

use crate::app::Root;
use crate::ui::theme;

/// 状态行停留时长。
///
/// 比全局 message 的 3 秒长一点：它不抢注意力，用户往往在处理别的事，
/// 错过就没有第二次机会；但也不能久留，否则会变成一条没人收走的旧文案。
pub const VISIBLE_FOR: Duration = Duration::from_secs(5);

/// 状态行的全部状态：文案、写入序号、写入时刻、已排过计时器的序号。
///
/// 四者必须一起变：单独写文案而不动序号，到期计时器就还在替旧文案计时。
/// 收在一个类型里，写入方只调 [`StatusLine::set`]，看不到这些细节。
pub(crate) struct StatusLine {
    text: String,
    /// 每写一条状态加一；计时器拿它判断「到期时还是不是同一条」。
    seq: u64,
    /// 写入时刻。`None` = 没有要显示的内容。
    since: Option<Instant>,
    /// 已经为哪个 `seq` 排过计时器。渲染每帧都跑，靠它避免每帧起一个后台任务。
    scheduled_seq: u64,
}

impl Default for StatusLine {
    fn default() -> Self {
        Self {
            text: String::new(),
            seq: 0,
            since: None,
            scheduled_seq: 0,
        }
    }
}

impl StatusLine {
    /// 写一条新状态：顶掉旧文案，重新开始计时。空文案等同于清空。
    pub(crate) fn set(&mut self, text: String) {
        self.seq = self.seq.wrapping_add(1);
        self.since = Some(Instant::now());
        self.text = text;
    }

    /// 清空。切页时调用：`status` 是全局反馈，不属于某一页，
    /// 留在新页面上就成了上一页的残留文案。
    pub(crate) fn clear(&mut self) {
        self.text.clear();
        self.since = None;
    }

    /// 最近一条状态的文案（不论是否还在显示窗口内）。
    pub(crate) fn text(&self) -> &str {
        &self.text
    }

    /// 现在该显示什么：空文案、没写过、或已过显示窗口都不显示。
    pub(crate) fn visible(&self, now: Instant) -> Option<&str> {
        let since = self.since?;
        if now.saturating_duration_since(since) >= VISIBLE_FOR {
            return None;
        }
        let text = self.text.trim();
        (!text.is_empty()).then_some(text)
    }

    /// 为当前这条状态认领一次到期计时：同一条状态只认领一次，返回认领到的序号。
    pub(crate) fn claim_timer(&mut self) -> Option<u64> {
        if self.scheduled_seq == self.seq {
            return None;
        }
        self.scheduled_seq = self.seq;
        Some(self.seq)
    }

    /// 计时到期：如果到期时还是同一条状态，收走它并返回 `true`。
    ///
    /// 期间写入过新状态（序号变了）或已经被切页清空，就什么都不做。
    pub(crate) fn expire(&mut self, seq: u64) -> bool {
        if self.seq != seq || self.since.is_none() {
            return false;
        }
        self.clear();
        true
    }
}

impl Root {
    /// 清空状态行。
    pub(crate) fn clear_status_line(&mut self) {
        self.status_line.clear();
    }

    /// 给当前这条状态挂到期计时器；计时器在渲染路径上按序号去重。
    pub(crate) fn schedule_status_clear(&mut self, cx: &mut Context<Self>) {
        let Some(seq) = self.status_line.claim_timer() else {
            return;
        };
        cx.spawn(async move |this, cx| {
            cx.background_executor().timer(VISIBLE_FOR).await;
            let _ = this.update(cx, |root, cx| {
                if root.status_line.expire(seq) {
                    cx.notify();
                }
            });
        })
        .detach();
    }
}

/// 渲染状态行；没有可显示的内容时返回 `None`。
///
/// 位置固定在播放栏上方、内容区左侧：与播放栏同一个视觉底部，又不挤占播放栏
/// 自己的三栏布局。用绝对定位，出现与消失都不推挤页面。它不挂任何交互处理器，
/// 所以在 gpui 里不产生命中框，压在页面上的几秒不会挡住下面列表的点击。
pub(crate) fn render(root: &mut Root, cx: &mut Context<Root>) -> Option<AnyElement> {
    let text = root.status_line.visible(Instant::now())?.to_string();
    root.schedule_status_clear(cx);
    Some(
        div()
            .id("status-line")
            .absolute()
            .bottom(px(theme::PLAYER_H + theme::space::SM))
            .left(px(theme::SIDEBAR_W + theme::space::LG))
            .max_w(px(520.0))
            .truncate()
            .px(px(theme::space::MD))
            .py(px(theme::space::SM))
            .rounded(px(theme::radius::CARD))
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_elevated())
            .shadow_lg()
            .text_size(theme::Text::Small.size())
            .text_color(theme::text())
            .child(text)
            .into_any_element(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fresh_status_is_visible() {
        let mut line = StatusLine::default();
        line.set("已收藏：晴天".to_string());
        assert_eq!(line.visible(Instant::now()), Some("已收藏：晴天"));
    }

    #[test]
    fn empty_or_never_written_status_never_shows() {
        let mut line = StatusLine::default();
        assert_eq!(line.visible(Instant::now()), None);
        line.set("   ".to_string());
        assert_eq!(line.visible(Instant::now()), None);
    }

    #[test]
    fn expired_status_disappears() {
        let mut line = StatusLine::default();
        line.set("正在加载推荐队列…".to_string());
        assert_eq!(line.visible(Instant::now() + VISIBLE_FOR), None);
    }

    #[test]
    fn status_survives_until_the_deadline() {
        let mut line = StatusLine::default();
        line.set("已退出登录".to_string());
        assert_eq!(
            line.visible(Instant::now() + (VISIBLE_FOR / 2)),
            Some("已退出登录")
        );
    }

    #[test]
    fn a_new_status_replaces_the_old_one_and_restarts_the_timer() {
        let mut line = StatusLine::default();
        line.set("音质已设为 无损，从下一首生效".to_string());
        let first = line.claim_timer();
        line.set("已开启详细日志".to_string());
        let second = line.claim_timer();
        assert!(first.is_some() && second.is_some());
        assert_ne!(first, second, "新状态要重新认领一次到期计时");
        assert_eq!(line.visible(Instant::now()), Some("已开启详细日志"));
    }

    #[test]
    fn only_the_latest_status_timer_can_expire_it() {
        let mut line = StatusLine::default();
        line.set("第一条".to_string());
        let first = line.claim_timer().expect("first status claims a timer");
        line.set("第二条".to_string());
        let second = line
            .claim_timer()
            .expect("second status claims its own timer");
        assert!(!line.expire(first), "旧计时器不该收走新文案");
        assert!(line.expire(second));
        assert_eq!(line.visible(Instant::now()), None);
    }

    #[test]
    fn clearing_now_hides_the_status_for_good() {
        let mut line = StatusLine::default();
        line.set("正在搜索「晴天」…".to_string());
        let seq = line.claim_timer().expect("status claims a timer");
        line.clear();
        assert_eq!(line.visible(Instant::now()), None);
        assert!(!line.expire(seq));
    }

    #[test]
    fn each_status_claims_exactly_one_timer() {
        let mut line = StatusLine::default();
        line.set("正在读取歌单…".to_string());
        assert!(line.claim_timer().is_some());
        assert_eq!(line.claim_timer(), None, "同一条状态不该每帧再排一次");
    }
}
