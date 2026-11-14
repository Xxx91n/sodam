//! 按住鼠标中键拖动页面时，只负责算「该滚到哪」。
//!
//! 这里不碰窗口，也不持有滚动句柄，全是普通数字，所以能直接单测。
//! 界面层把事件喂进来，再把算出的偏移写回滚动句柄。

use crate::app::Nav;

/// 起步死区：鼠标没挪够 2px 就不滚，免得中键轻点让页面抖一下。
const DEAD_ZONE: f32 = 2.0;

/// 按下时选中的滚动区。一次拖动只认这一个，中途不换目标。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MiddleDragTarget {
    /// 设置页：普通滚动句柄，直接写绝对偏移。
    Settings,
    /// 六个长列表：`ListState`，只吃按像素的增量。
    List(MiddleDragList),
}

/// 六个参与中键拖动的长列表。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MiddleDragList {
    /// 听歌模式页。
    Scenes,
    /// 我喜欢的音乐详情。
    LikedDetail,
    /// 我的歌单详情。
    LibraryDetail,
    /// 搜索里点开的歌单详情。
    SearchPlaylistDetail,
    /// 音乐人详情。
    ArtistDetail,
    /// 专辑详情。
    AlbumDetail,
}

/// 按下时记下的起点。`top` 是内容离顶部的距离，0 表示已经在最顶上。
#[derive(Clone, Copy)]
struct Anchor {
    y: f32,
    top: f32,
    page: Nav,
    /// 这次拖动锁定的滚动区。
    target: MiddleDragTarget,
    /// 已经挪够 2px、开始滚了。起步之后不再判死区，否则拖回起点会卡住。
    started: bool,
}

/// 一次中键拖动。`None` 表示现在没在拖。
#[derive(Clone, Copy, Default)]
pub struct MiddleDrag(Option<Anchor>);

impl MiddleDrag {
    /// 按下中键。已经按着就忽略：重复按下不会把起点挪走，也不会叠加位移。
    pub fn begin(&mut self, y: f32, top: f32, page: Nav, target: MiddleDragTarget) {
        if self.0.is_none() {
            self.0 = Some(Anchor {
                y,
                top,
                page,
                target,
                started: false,
            });
        }
    }

    /// 这次拖动锁定的滚动区；没在拖就是 `None`。
    pub fn target(&self) -> Option<MiddleDragTarget> {
        self.0.map(|anchor| anchor.target)
    }

    /// 松开中键、切页、窗口失焦，都走这里收尾。
    pub fn finish(&mut self) {
        self.0 = None;
    }

    /// 页面换了或窗口失焦，当场结束；之后鼠标再动也不滚。
    pub fn sync_context(&mut self, page: Nav, window_active: bool) {
        if self
            .0
            .is_some_and(|anchor| anchor.page != page || !window_active)
        {
            self.0 = None;
        }
    }

    /// 鼠标移到 `y`，算出新的「离顶部距离」。
    /// 返回 `None` 就是这次不用滚：没在拖、还没过死区，或者上下文已经失效。
    pub fn move_to(&mut self, y: f32, max_top: f32, page: Nav, window_active: bool) -> Option<f32> {
        self.sync_context(page, window_active);
        let mut anchor = self.0?;
        let moved = y - anchor.y;
        // 死区只在起步前判一次。起步之后哪怕拖回按下点，也要继续 1:1 跟手。
        if !anchor.started {
            if moved.abs() < DEAD_ZONE {
                return None;
            }
            anchor.started = true;
            self.0 = Some(anchor);
        }
        // 往下拖，内容跟着往下走，离顶部就近了；往上拖反过来。
        Some((anchor.top - moved).clamp(0.0, max_top))
    }

    /// 给只吃增量的列表用：算出这一帧该滚多少像素。
    /// `current_top` 是列表眼下的真实位置；目标已经夹在 0 到最大偏移之间，
    /// 所以到边时增量自然收成 0，剩下的距离不会漏给外层。
    pub fn move_by(
        &mut self,
        y: f32,
        current_top: f32,
        max_top: f32,
        page: Nav,
        window_active: bool,
    ) -> Option<f32> {
        let target_top = self.move_to(y, max_top, page, window_active)?;
        Some(target_top - current_top)
    }
}

#[cfg(test)]
mod tests {
    use super::{MiddleDrag, MiddleDragList, MiddleDragTarget};
    use crate::app::Nav;

    const SETTINGS: Nav = Nav::Settings;
    const HOME: Nav = Nav::Home;
    const TARGET: MiddleDragTarget = MiddleDragTarget::Settings;
    const SCENES: MiddleDragTarget = MiddleDragTarget::List(MiddleDragList::Scenes);

    fn dragging(at: f32, top: f32) -> MiddleDrag {
        let mut drag = MiddleDrag::default();
        drag.begin(at, top, SETTINGS, TARGET);
        drag
    }

    /// 不到 2px 一动不动，正好 2px 就开始跟手。
    #[test]
    fn small_moves_do_not_scroll() {
        let mut drag = dragging(100.0, 50.0);
        assert_eq!(drag.move_to(101.0, 500.0, SETTINGS, true), None);
        assert_eq!(drag.move_to(99.5, 500.0, SETTINGS, true), None);
        assert_eq!(drag.move_to(102.0, 500.0, SETTINGS, true), Some(48.0));
        assert_eq!(drag.move_to(98.0, 500.0, SETTINGS, true), Some(52.0));
    }

    /// 起步之后往回拖也跟手，不会再被 2px 死区拦住。
    #[test]
    fn moving_back_after_start_still_follows_the_pointer() {
        let mut drag = dragging(100.0, 50.0);
        assert_eq!(drag.move_to(130.0, 500.0, SETTINGS, true), Some(20.0));
        // 拖回按下点：必须给出 50，不能因为「总位移不到 2px」又停下。
        assert_eq!(drag.move_to(100.0, 500.0, SETTINGS, true), Some(50.0));
        assert_eq!(drag.move_to(101.0, 500.0, SETTINGS, true), Some(49.0));
        assert_eq!(drag.move_to(99.0, 500.0, SETTINGS, true), Some(51.0));
        // 越过起点继续往上拖也一样跟手。
        assert_eq!(drag.move_to(80.0, 500.0, SETTINGS, true), Some(70.0));
    }

    /// 鼠标移多少内容就移多少：往下拖内容往下走，往上拖内容往上走。
    #[test]
    fn pointer_moves_one_to_one() {
        let mut drag = dragging(100.0, 80.0);
        assert_eq!(drag.move_to(130.0, 500.0, SETTINGS, true), Some(50.0));
        assert_eq!(drag.move_to(70.0, 500.0, SETTINGS, true), Some(110.0));
    }

    /// 到顶就停住，不会滚出负的偏移。
    #[test]
    fn stops_at_the_top() {
        let mut drag = dragging(100.0, 10.0);
        assert_eq!(drag.move_to(200.0, 500.0, SETTINGS, true), Some(0.0));
    }

    /// 到底就停住，剩下的距离不会冒到外层去。
    #[test]
    fn stops_at_the_bottom() {
        let mut drag = dragging(100.0, 10.0);
        assert_eq!(drag.move_to(-400.0, 100.0, SETTINGS, true), Some(100.0));
    }

    /// 松开之后，再怎么移动都不滚。
    #[test]
    fn release_stops_the_drag() {
        let mut drag = dragging(100.0, 50.0);
        drag.finish();
        assert_eq!(drag.move_to(300.0, 500.0, SETTINGS, true), None);
    }

    /// 窗口失焦当场停，之后就算焦点回来也不接着滚。
    #[test]
    fn losing_focus_stops_the_drag() {
        let mut drag = dragging(100.0, 50.0);
        assert_eq!(drag.move_to(200.0, 500.0, SETTINGS, false), None);
        assert_eq!(drag.move_to(300.0, 500.0, SETTINGS, true), None);
    }

    /// 切页当场停，回到原来的页面也不接着滚。
    #[test]
    fn changing_page_stops_the_drag() {
        let mut drag = dragging(100.0, 50.0);
        assert_eq!(drag.move_to(200.0, 500.0, HOME, true), None);
        assert_eq!(drag.move_to(300.0, 500.0, SETTINGS, true), None);
    }

    /// 只切页或只失焦、鼠标一下没动，状态也会清掉。
    #[test]
    fn context_change_clears_without_mouse_move() {
        let mut drag = dragging(100.0, 50.0);
        drag.sync_context(HOME, true);
        assert_eq!(drag.move_to(300.0, 500.0, SETTINGS, true), None);

        let mut drag = dragging(100.0, 50.0);
        drag.sync_context(SETTINGS, false);
        assert_eq!(drag.move_to(300.0, 500.0, SETTINGS, true), None);

        let mut drag = dragging(100.0, 50.0);
        drag.sync_context(SETTINGS, true);
        assert_eq!(drag.move_to(130.0, 500.0, SETTINGS, true), Some(20.0));
    }

    /// 拖着的时候又按一次中键，起点不挪，位移也不叠。
    #[test]
    fn pressing_again_does_not_restart_or_stack() {
        let mut drag = dragging(100.0, 50.0);
        drag.begin(180.0, 10.0, SETTINGS, TARGET);
        assert_eq!(drag.move_to(130.0, 500.0, SETTINGS, true), Some(20.0));
    }

    /// 按下时选定目标，拖动途中不换；松开、切页、失焦都会把它清掉。
    #[test]
    fn target_is_locked_until_the_drag_ends() {
        let mut drag = MiddleDrag::default();
        assert_eq!(drag.target(), None);
        drag.begin(100.0, 50.0, SETTINGS, SCENES);
        assert_eq!(drag.target(), Some(SCENES));

        drag.begin(
            180.0,
            10.0,
            SETTINGS,
            MiddleDragTarget::List(MiddleDragList::AlbumDetail),
        );
        assert_eq!(drag.target(), Some(SCENES));
        assert_eq!(drag.move_to(130.0, 500.0, SETTINGS, true), Some(20.0));
        assert_eq!(drag.target(), Some(SCENES));

        drag.finish();
        assert_eq!(drag.target(), None);

        let mut drag = MiddleDrag::default();
        drag.begin(100.0, 50.0, SETTINGS, TARGET);
        drag.sync_context(HOME, true);
        assert_eq!(drag.target(), None);

        let mut drag = MiddleDrag::default();
        drag.begin(100.0, 50.0, SETTINGS, TARGET);
        drag.sync_context(SETTINGS, false);
        assert_eq!(drag.target(), None);
    }

    /// 列表吃增量：算出的目标和当前位置之差就是这一帧该滚的距离。
    #[test]
    fn move_by_returns_the_step_from_the_current_offset() {
        let mut drag = dragging(100.0, 50.0);
        // 往下拖 30px：目标 20，当前 50，所以要往回滚 30。
        assert_eq!(
            drag.move_by(130.0, 50.0, 500.0, SETTINGS, true),
            Some(-30.0)
        );
        // 下一帧列表已经到 20；再往下拖 10px，只滚 10。
        assert_eq!(
            drag.move_by(140.0, 20.0, 500.0, SETTINGS, true),
            Some(-10.0)
        );
    }

    /// 到底之后增量收成 0，剩下的距离不会漏到外层。
    #[test]
    fn move_by_stops_at_the_edge() {
        let mut drag = dragging(100.0, 10.0);
        assert_eq!(
            drag.move_by(-400.0, 10.0, 100.0, SETTINGS, true),
            Some(90.0)
        );
        assert_eq!(
            drag.move_by(-500.0, 100.0, 100.0, SETTINGS, true),
            Some(0.0)
        );
    }

    /// 没起步、松手、切页、失焦，都不给增量。
    #[test]
    fn move_by_is_silent_when_the_drag_is_invalid() {
        let mut drag = dragging(100.0, 50.0);
        assert_eq!(drag.move_by(101.0, 50.0, 500.0, SETTINGS, true), None);

        let mut drag = dragging(100.0, 50.0);
        drag.finish();
        assert_eq!(drag.move_by(200.0, 50.0, 500.0, SETTINGS, true), None);

        let mut drag = dragging(100.0, 50.0);
        assert_eq!(drag.move_by(200.0, 50.0, 500.0, HOME, true), None);

        let mut drag = dragging(100.0, 50.0);
        assert_eq!(drag.move_by(200.0, 50.0, 500.0, SETTINGS, false), None);
    }
}
