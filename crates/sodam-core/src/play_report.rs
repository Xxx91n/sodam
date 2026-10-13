//! 播放进度 / 时长上报。
//!
//! 官方客户端把「进度 / 时长」交给 applog 埋点（`mcs.zijieapi.com`），把「播放计数」
//! 交给业务接口 `ReportAction`。报文与请求都在 `libresoda::soda::report` 里，本模块只
//! 负责**跟踪播放状态**（开播 / 首次进度 / 暂停 / 播完 / 切歌），再调用 libresoda。
//!
//! 所有网络调用都在后台线程里做，绝不阻塞 UI / 音频线程。

use std::time::Instant;

use libresoda::soda::media_ref::MediaRef;
use libresoda::{ApplogIdentity, PlayAction, PlayEndReason, Soda};

use crate::audio::PlaybackSnapshot;
use crate::config::Settings;
use crate::session::Session;

/// 单次观察的最大计时间隔（毫秒）。系统睡眠 / 卡顿后的巨大会话被截断，
/// 避免把「实际没播」的时间算进时长。
const MAX_TICK_MS: i64 = 1_000;

/// 首次进度上报阈值（秒）：进度越过它才认为「真的开始放了」。
const PROGRESS_THRESHOLD_SECONDS: f64 = 0.5;

/// 当前这一首的跟踪状态。
#[derive(Debug, Clone)]
struct CurrentPlay {
    track_id: String,
    duration_seconds: f64,
    /// 实际播放毫秒（暂停不计）。
    played_ms: i64,
    /// 首次进度是否已上报（官方 `progressedReported`）。
    progress_reported: bool,
    /// 是否观察到播放完成（引擎 `finished`）。
    finished: bool,
}

/// 播放上报器：由 UI 心跳周期性喂 [`PlaybackSnapshot`]。
pub struct PlayReporter {
    settings: Settings,
    identity: ApplogIdentity,
    current: Option<CurrentPlay>,
    last_observe: Instant,
    /// 上一拍是否在播（识别「播放 → 暂停」）。
    was_playing: bool,
    /// 是否真的发网络请求（单测里关掉，避免真发埋点）。
    emit: bool,
}

impl PlayReporter {
    pub fn new(settings: Settings) -> Self {
        let identity = ApplogIdentity {
            device_id: settings.device_id.trim().to_string(),
            os_name: std::env::consts::OS.to_string(),
            ..Default::default()
        };
        Self {
            settings,
            identity,
            current: None,
            last_observe: Instant::now(),
            was_playing: false,
            emit: true,
        }
    }

    /// 单测用：状态机照常跑，但不发任何网络请求。
    #[cfg(test)]
    pub fn silent(settings: Settings) -> Self {
        let mut reporter = Self::new(settings);
        reporter.emit = false;
        reporter
    }

    /// 账号信息就绪后补上 `user_id`（埋点用它归属到账号）。
    pub fn set_user_id(&mut self, user_id: impl Into<String>) {
        self.identity.user_id = user_id.into();
    }

    /// 设置变更时同步（设备指纹 / 签名器地址可能变）。
    pub fn apply_settings(&mut self, settings: Settings) {
        self.identity.device_id = settings.device_id.trim().to_string();
        self.settings = settings;
    }

    /// 喂一拍播放快照（UI 心跳每 ~200ms 调一次）。
    pub fn observe(&mut self, snapshot: &PlaybackSnapshot) {
        self.observe_at(snapshot, Instant::now());
    }

    /// 同上，但由调用方给定时刻（单测注入时间）。
    pub fn observe_at(&mut self, snapshot: &PlaybackSnapshot, now: Instant) {
        let delta_ms = now
            .saturating_duration_since(self.last_observe)
            .as_millis()
            .min(MAX_TICK_MS as u128) as i64;
        self.last_observe = now;

        // 1) 曲目变化：结束上一首，开始新的一首。
        let snapshot_id = snapshot.track_id.trim();
        let current_id = self.current.as_ref().map(|c| c.track_id.as_str());
        if current_id != Some(snapshot_id) {
            if let Some(previous) = self.current.take() {
                let reason = if previous.finished {
                    PlayEndReason::Finished
                } else {
                    PlayEndReason::Next
                };
                self.report_end(previous, reason);
            }
            if !snapshot_id.is_empty() {
                let duration = if snapshot.duration_seconds > 0.0 {
                    snapshot.duration_seconds
                } else {
                    0.0
                };
                let media = MediaRef::track(snapshot_id);
                self.spawn_start(media);
                self.current = Some(CurrentPlay {
                    track_id: snapshot_id.to_string(),
                    duration_seconds: duration,
                    played_ms: 0,
                    progress_reported: false,
                    finished: false,
                });
            }
        }

        // 2) 计时 + 首次进度。
        let mut progress_to_report = None;
        if let Some(current) = self.current.as_mut() {
            if snapshot.duration_seconds > 0.0 {
                current.duration_seconds = snapshot.duration_seconds;
            }
            if snapshot.playing {
                current.played_ms = current.played_ms.saturating_add(delta_ms);
                if !current.progress_reported
                    && snapshot.position_seconds > PROGRESS_THRESHOLD_SECONDS
                {
                    current.progress_reported = true;
                    progress_to_report = Some((
                        current.track_id.clone(),
                        snapshot.position_seconds,
                        current.duration_seconds,
                    ));
                }
            }
            if snapshot.finished {
                current.finished = true;
            }
        }
        if let Some((track_id, progress, duration)) = progress_to_report {
            self.spawn_progress(MediaRef::track(track_id), progress, duration);
        }

        // 3) 「播放 → 暂停」：上报一次时长（官方 `audio_over` / `pause`）。
        if self.was_playing && !snapshot.playing {
            if let Some(current) = self.current.as_ref() {
                if !current.finished && current.played_ms > 0 {
                    self.report_end(current.clone(), PlayEndReason::Pause);
                }
            }
        }
        self.was_playing = snapshot.playing;
    }

    /// 内存里当前曲目的已播放毫秒（测试 / 诊断用）。
    pub fn played_ms(&self) -> i64 {
        self.current.as_ref().map(|c| c.played_ms).unwrap_or(0)
    }

    /// 当前曲目是否已上报过首次进度。
    pub fn progress_reported(&self) -> bool {
        self.current
            .as_ref()
            .map(|c| c.progress_reported)
            .unwrap_or(false)
    }

    fn report_end(&self, current: CurrentPlay, reason: PlayEndReason) {
        let finished = current.finished;
        let media = MediaRef::track(current.track_id);
        self.spawn_duration(
            media,
            current.played_ms,
            current.duration_seconds,
            reason,
            finished,
        );
    }

    // -- 后台线程：构造 Session → 调 libresoda ------------------------------------

    fn spawn_start(&self, media: MediaRef) {
        if !self.emit {
            return;
        }
        let settings = self.settings.clone();
        let identity = self.identity.clone();
        spawn(settings, move |soda| {
            let effective = effective_identity(soda, &identity);
            log_report(
                "identity",
                &media.id,
                &format!(
                    "user_id={:?} device_id={:?}",
                    effective.user_id, effective.device_id
                ),
            );
            // 写「最近播放」：手机 / 其它端的历史播放读的就是这条
            // （`append_recently_played_media`，与埋点/播放计数是不同接口）。
            log_report(
                "recent",
                &media.id,
                &describe(soda.append_recently_played_media(std::slice::from_ref(&media))),
            );
            log_report(
                "start",
                &media.id,
                &describe(soda.report_play_start(&effective, &media)),
            );
            // 播放计数（业务接口）；签名服务没配时失败，忽略即可。
            log_report(
                "action",
                &media.id,
                &describe(soda.report_play_action(&PlayAction::track(media.id.clone()))),
            );
        });
    }

    fn spawn_progress(&self, media: MediaRef, progress: f64, duration: f64) {
        if !self.emit {
            return;
        }
        let settings = self.settings.clone();
        let identity = self.identity.clone();
        spawn(settings, move |soda| {
            log_report(
                "progress",
                &media.id,
                &describe(soda.report_play_progress(
                    &effective_identity(soda, &identity),
                    &media,
                    progress,
                    duration,
                    true,
                )),
            );
        });
    }

    fn spawn_duration(
        &self,
        media: MediaRef,
        played_ms: i64,
        duration: f64,
        reason: PlayEndReason,
        finished: bool,
    ) {
        if !self.emit {
            return;
        }
        let settings = self.settings.clone();
        let identity = self.identity.clone();
        spawn(settings, move |soda| {
            // sodam 暂不分前后台，全部记为前台。
            log_report(
                "duration",
                &media.id,
                &describe(soda.report_play_duration(
                    &effective_identity(soda, &identity),
                    &media,
                    played_ms,
                    duration,
                    reason,
                    played_ms,
                    0,
                    finished,
                )),
            );
        });
    }
}

/// 用 `Soda` 里的设备指纹补齐身份（调用方只保证 `device_id` / `user_id` 有值）。
fn effective_identity(soda: &Soda, identity: &ApplogIdentity) -> ApplogIdentity {
    let mut effective = ApplogIdentity::from_soda(soda);
    effective.user_id = identity.user_id.clone();
    if effective.device_id.trim().is_empty() {
        effective.device_id = identity.device_id.clone();
    }
    if !identity.app_version.trim().is_empty() {
        effective.app_version = identity.app_version.clone();
    }
    effective
}

/// 给日志用的上报结果描述（`SODAM_REPORT_LOG=1` 时打印），带上服务端回包摘要。
fn describe(result: libresoda::Result<serde_json::Value>) -> String {
    match result {
        Ok(value) => {
            let text = value.to_string();
            let text: String = if text.chars().count() > 180 {
                format!("{}…", text.chars().take(180).collect::<String>())
            } else {
                text
            };
            format!("ok {text}")
        }
        Err(err) => format!("err {err}"),
    }
}

fn log_report(kind: &str, track_id: &str, result: &str) {
    if std::env::var("SODAM_REPORT_LOG").is_ok() {
        eprintln!("[report] {kind} track={track_id} -> {result}");
    }
}

/// 在后台线程里构造会话并执行上报；失败只记录，不影响播放。
fn spawn<F>(settings: Settings, f: F)
where
    F: FnOnce(&Soda) + Send + 'static,
{
    let _ = std::thread::Builder::new()
        .name("sodam-report".to_string())
        .spawn(move || {
            let session = Session::new(settings);
            f(session.soda());
        });
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn snapshot(track: &str, position: f64, playing: bool) -> PlaybackSnapshot {
        PlaybackSnapshot {
            track_id: track.to_string(),
            duration_seconds: 120.0,
            position_seconds: position,
            playing,
            ..Default::default()
        }
    }

    #[test]
    fn accumulates_played_time_while_playing() {
        let mut reporter = PlayReporter::silent(Settings::default());
        let t0 = Instant::now();
        reporter.observe_at(&snapshot("a", 0.0, true), t0);
        reporter.observe_at(&snapshot("a", 1.0, true), t0 + Duration::from_millis(1000));
        reporter.observe_at(&snapshot("a", 2.0, true), t0 + Duration::from_millis(2000));
        assert_eq!(reporter.played_ms(), 2000);
    }

    #[test]
    fn paused_time_is_not_counted() {
        let mut reporter = PlayReporter::silent(Settings::default());
        let t0 = Instant::now();
        reporter.observe_at(&snapshot("a", 0.0, true), t0);
        reporter.observe_at(&snapshot("a", 1.0, true), t0 + Duration::from_millis(1000));
        // 暂停 5 秒
        reporter.observe_at(&snapshot("a", 1.0, false), t0 + Duration::from_millis(6000));
        assert_eq!(reporter.played_ms(), 1000);
        // 恢复播放 1 秒
        reporter.observe_at(&snapshot("a", 2.0, true), t0 + Duration::from_millis(7000));
        assert_eq!(reporter.played_ms(), 2000);
    }

    #[test]
    fn progress_reported_once_after_threshold() {
        let mut reporter = PlayReporter::silent(Settings::default());
        let t0 = Instant::now();
        reporter.observe_at(&snapshot("a", 0.0, true), t0);
        assert!(!reporter.progress_reported());
        reporter.observe_at(&snapshot("a", 0.2, true), t0 + Duration::from_millis(200));
        assert!(!reporter.progress_reported(), "低于阈值不上报");
        reporter.observe_at(&snapshot("a", 1.2, true), t0 + Duration::from_millis(1200));
        assert!(reporter.progress_reported());
    }

    #[test]
    fn track_change_resets_played_time() {
        let mut reporter = PlayReporter::silent(Settings::default());
        let t0 = Instant::now();
        reporter.observe_at(&snapshot("a", 0.0, true), t0);
        reporter.observe_at(&snapshot("a", 1.0, true), t0 + Duration::from_millis(1000));
        reporter.observe_at(&snapshot("a", 2.0, true), t0 + Duration::from_millis(2000));
        reporter.observe_at(&snapshot("a", 3.0, true), t0 + Duration::from_millis(3000));
        assert_eq!(reporter.played_ms(), 3000);
        reporter.observe_at(&snapshot("b", 0.0, true), t0 + Duration::from_millis(3000));
        assert_eq!(reporter.played_ms(), 0, "换曲后重新计时");
    }
}
