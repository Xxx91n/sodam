//! 全局 message：Ant Design 风格的多条轻提示队列。

use std::time::Duration;

use gpui::prelude::*;
use gpui::{div, px, AnyElement, Context};

use crate::app::Root;
use crate::ui::theme;

/// 默认显示时长，与 Ant Design message 的默认值一致。
pub const DEFAULT_DURATION: Duration = Duration::from_secs(3);

#[allow(dead_code)] // public message API: Error is used by callers outside this crate's binary tests
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageKind {
    Info,
    Success,
    Warning,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub id: u64,
    pub kind: MessageKind,
    pub text: String,
    /// `None` 表示不自动关闭；默认见 [`DEFAULT_DURATION`]。
    pub duration: Option<Duration>,
}

impl Message {
    fn accent(&self) -> gpui::Rgba {
        match self.kind {
            MessageKind::Info => theme::text_muted(),
            MessageKind::Success => theme::accent(),
            MessageKind::Warning => theme::warning(),
            MessageKind::Error => theme::danger(),
        }
    }

    fn icon(&self) -> &'static str {
        match self.kind {
            MessageKind::Info => "i",
            MessageKind::Success => "✓",
            MessageKind::Warning => "!",
            MessageKind::Error => "×",
        }
    }
}

impl Root {
    /// 打开一条全局 message；返回 ID，可用于 [`Root::close_message`]。
    pub fn open_message(&mut self, kind: MessageKind, text: impl Into<String>) -> u64 {
        self.push_message(kind, text, Some(DEFAULT_DURATION))
    }

    pub fn push_message(
        &mut self,
        kind: MessageKind,
        text: impl Into<String>,
        duration: Option<Duration>,
    ) -> u64 {
        self.next_message_id = self.next_message_id.wrapping_add(1);
        let id = self.next_message_id;
        self.messages.push(Message {
            id,
            kind,
            text: text.into(),
            duration,
        });
        id
    }

    pub fn close_message(&mut self, id: u64) -> bool {
        let before = self.messages.len();
        self.messages.retain(|message| message.id != id);
        self.messages.len() != before
    }

    /// 启动该条消息的计时器；消息被替换/关闭后计时器会安全退出。
    pub(crate) fn schedule_message_close(&mut self, id: u64, cx: &mut Context<Self>) {
        let Some(message) = self.messages.iter().find(|message| message.id == id) else {
            return;
        };
        let Some(duration) = message.duration else {
            return;
        };
        cx.spawn(async move |this, cx| {
            cx.background_executor().timer(duration).await;
            let _ = this.update(cx, |root, cx| {
                if root.close_message(id) {
                    cx.notify();
                }
            });
        })
        .detach();
    }
}

/// 最高层浮层：多条消息按插入顺序堆叠，各自独立计时。
pub(crate) fn render(root: &mut Root, cx: &mut Context<Root>) -> Option<AnyElement> {
    if root.messages.is_empty() {
        return None;
    }
    let ids: Vec<u64> = root
        .messages
        .iter()
        .filter_map(|message| message.duration.map(|_| message.id))
        .collect();
    for id in ids {
        if root.message_timers.insert(id) {
            root.schedule_message_close(id, cx);
        }
    }
    root.message_timers
        .retain(|id| root.messages.iter().any(|message| message.id == *id));

    let messages = root.messages.clone();
    Some(
        gpui::deferred(
            div()
                .id("global-messages")
                .absolute()
                .top(px(48.0))
                .right(px(24.0))
                .flex()
                .flex_col()
                .items_end()
                .gap(px(theme::space::SM))
                .children(messages.into_iter().map(|message| {
                    let accent = message.accent();
                    let id = message.id;
                    div()
                        .id(("message", id as usize))
                        .flex()
                        .flex_row()
                        .items_center()
                        .gap(px(theme::space::SM))
                        .max_w(px(520.0))
                        .px(px(theme::space::LG))
                        .py(px(theme::space::SM))
                        .rounded(px(theme::radius::CARD))
                        .border_1()
                        .border_color(accent)
                        .bg(theme::surface_elevated())
                        .text_color(theme::text())
                        .text_size(theme::Text::Small.size())
                        .shadow_lg()
                        .child(div().flex_none().text_color(accent).child(message.icon()))
                        .child(message.text)
                        .on_click(cx.listener(move |root, _, _, cx| {
                            if root.close_message(id) {
                                root.message_timers.remove(&id);
                                cx.notify();
                            }
                        }))
                        .into_any_element()
                })),
        )
        .with_priority(usize::MAX)
        .into_any_element(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_message_uses_three_seconds() {
        assert_eq!(DEFAULT_DURATION, Duration::from_secs(3));
    }

    #[test]
    fn message_kinds_have_distinct_visual_tokens() {
        let base = Message {
            id: 1,
            kind: MessageKind::Info,
            text: "info".into(),
            duration: None,
        };
        let success = Message {
            kind: MessageKind::Success,
            ..base.clone()
        };
        let warning = Message {
            kind: MessageKind::Warning,
            ..base.clone()
        };
        let error = Message {
            kind: MessageKind::Error,
            ..base
        };
        assert_ne!(success.icon(), warning.icon());
        assert_ne!(warning.icon(), error.icon());
    }
}
