//! 底部状态行：`Root::status` 的唯一渲染出口（#83）。
//!
//! `status` 是全仓库约百处写入的普通操作反馈（切档、开关、收藏、加载中…）。
//! 它以前只写不画，用户看不到；这里给它一个固定位置：播放栏上方左侧一行，
//! 停留 [`VISIBLE_FOR`] 后自行消失。重要的、需要打断的事件仍然走
//! [`crate::ui::message`] 的全局轻提示，两条通道互不替代。

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

/// 状态行当前应当显示什么。
///
/// 单独抽成纯函数，好断言「空文案不显示」「过期不显示」这两条生命周期，
/// 不必为了它们搭一个 GPUI 上下文。
fn visible_text(status: &str, since: Option<Instant>, now: Instant) -> Option<&str> {
    let since = since?;
    if now.saturating_duration_since(since) >= VISIBLE_FOR {
        return None;
    }
    let text = status.trim();
    (!text.is_empty()).then_some(text)
}

impl Root {
    /// 清空状态行。换页时调用：`status` 是全局反馈，不属于某一页，
    /// 留在新页面上就成了上一页的残留文案。
    pub(crate) fn clear_status_line(&mut self) {
        self.status_since = None;
        self.status.clear();
    }

    /// 给当前这条状态挂一个到期计时器；被新状态顶掉后计时器自行作废。
    ///
    /// 计时器在渲染路径上按 `status_seq` 去重：渲染是每帧都跑的，
    /// 不记「已经为本序号排过一次」，这里会每帧起一个后台任务。
    pub(crate) fn schedule_status_clear(&mut self, cx: &mut Context<Self>) {
        if self.status_timer_seq == self.status_seq {
            return;
        }
        self.status_timer_seq = self.status_seq;
        let seq = self.status_seq;
        cx.spawn(async move |this, cx| {
            cx.background_executor().timer(VISIBLE_FOR).await;
            let _ = this.update(cx, |root, cx| {
                if root.status_seq == seq && root.status_since.is_some() {
                    root.clear_status_line();
                    cx.notify();
                }
            });
        })
        .detach();
    }
}

/// 渲染状态行；没有可显示的内容时返回 `None`。
///
/// 位置固定在播放栏上方、内容区左侧：与播放栏同一个视觉底部，
/// 又不挤占播放栏自己的三栏布局。用 absolute 定位，出现与消失都不推挤页面。
pub(crate) fn render(root: &mut Root, cx: &mut Context<Root>) -> Option<AnyElement> {
    let text = visible_text(&root.status, root.status_since, Instant::now())?.to_string();
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
        let now = Instant::now();
        assert_eq!(
            visible_text("已收藏：晴天", Some(now), now),
            Some("已收藏：晴天")
        );
    }

    #[test]
    fn empty_status_never_shows() {
        let now = Instant::now();
        assert_eq!(visible_text("   ", Some(now), now), None);
        assert_eq!(visible_text("", Some(now), now), None);
        assert_eq!(visible_text("已收藏", None, now), None);
    }

    #[test]
    fn expired_status_disappears() {
        let since = Instant::now();
        let now = since + VISIBLE_FOR;
        assert_eq!(visible_text("正在加载推荐队列…", Some(since), now), None);
    }

    #[test]
    fn status_survives_until_the_deadline() {
        let since = Instant::now();
        let now = since + (VISIBLE_FOR / 2);
        assert_eq!(
            visible_text("已退出登录", Some(since), now),
            Some("已退出登录")
        );
    }
}
