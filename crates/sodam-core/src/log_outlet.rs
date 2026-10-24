//! 诊断日志出口：本机日志目录解析、按大小轮转、保留份数与内存降级。
//!
//! 设计规则（见 Issue #57 / #53）：
//! - 目录在用户数据目录，默认开启（INFO 级）；
//! - 单文件 5 MB 轮转，最多保留 5 份旧文件；
//! - 目录不可写时不 panic、不阻塞，只在内存中降级缓冲；
//! - 写盘前切断 URL 查询串，杜绝敏感 Token 落盘。

use std::collections::VecDeque;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::SystemTime;

pub const DEFAULT_MAX_FILE_SIZE: u64 = 5 * 1024 * 1024; // 5 MB
pub const DEFAULT_MAX_OLD_FILES: usize = 5;
pub const LOG_FILE_NAME: &str = "sodam.log";
pub const MEMORY_BUFFER_LIMIT: usize = 500;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    Windows,
    Linux,
    MacOS,
}

/// 解析指定平台下的日志根目录。
pub fn resolve_platform_log_dir(
    platform: Platform,
    local_app_data: Option<&Path>,
    state_dir: Option<&Path>,
    data_dir: Option<&Path>,
    home_dir: Option<&Path>,
) -> PathBuf {
    match platform {
        Platform::Windows => local_app_data
            .map(Path::to_path_buf)
            .unwrap_or_else(std::env::temp_dir)
            .join("sodam")
            .join("logs"),
        Platform::MacOS => data_dir
            .map(Path::to_path_buf)
            .unwrap_or_else(std::env::temp_dir)
            .join("sodam")
            .join("logs"),
        Platform::Linux => state_dir
            .map(Path::to_path_buf)
            .or_else(|| home_dir.map(|h| h.join(".local").join("state")))
            .unwrap_or_else(std::env::temp_dir)
            .join("sodam")
            .join("logs"),
    }
}

/// 获取当前平台的日志目录；若设置了 `SODAM_LOG_DIR` 环境变量则优先使用。
pub fn log_dir() -> PathBuf {
    if let Some(path) = std::env::var_os("SODAM_LOG_DIR").filter(|p| !p.is_empty()) {
        return PathBuf::from(path);
    }
    default_log_dir()
}

fn default_log_dir() -> PathBuf {
    #[cfg(target_os = "windows")]
    let platform = Platform::Windows;
    #[cfg(target_os = "macos")]
    let platform = Platform::MacOS;
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    let platform = Platform::Linux;

    resolve_platform_log_dir(
        platform,
        dirs::data_local_dir().as_deref(),
        dirs::state_dir().as_deref(),
        dirs::data_dir().as_deref(),
        dirs::home_dir().as_deref(),
    )
}

/// 格式化 UTC 时间戳为 `YYYY-MM-DDTHH:MM:SSZ` 格式。
pub fn format_utc_timestamp(now: SystemTime) -> String {
    let duration = now
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let secs = duration.as_secs();
    let day_secs = (secs % 86400) as u32;
    let hour = day_secs / 3600;
    let minute = (day_secs % 3600) / 60;
    let second = day_secs % 60;

    let days = (secs / 86400) as i64;
    let (y, m, d) = civil_from_days(days);
    format!("{y:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}Z")
}

// Howard Hinnant 民用历算法转换：将自 UNIX_EPOCH 以来的天数转换为年月日
fn civil_from_days(days: i64) -> (i32, u32, u32) {
    let z = days + 719468;
    let era = (if z >= 0 { z } else { z - 146096 }) / 146097; // 400 年周期序号
    let doe = (z - era * 146097) as u32; // day of era [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; // year of era [0, 399]
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // day of year [0, 365]
    let mp = (5 * doy + 2) / 153; // month index [0, 11] (3月起计)
    let d = doy - (153 * mp + 2) / 5 + 1; // day of month [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 }; // 还原公历月 [1, 12]
    let y = if m <= 2 { y + 1 } else { y };
    (y as i32, m, d)
}

fn rotate_files(log_dir: &Path, max_old_files: usize) -> std::io::Result<()> {
    if max_old_files > 0 {
        let oldest = log_dir.join(format!("{LOG_FILE_NAME}.{max_old_files}"));
        if oldest.exists() {
            let _ = fs::remove_file(&oldest);
        }
        for i in (1..max_old_files).rev() {
            let src = log_dir.join(format!("{LOG_FILE_NAME}.{i}"));
            if src.exists() {
                let dst = log_dir.join(format!("{LOG_FILE_NAME}.{}", i + 1));
                fs::rename(&src, &dst)?;
            }
        }
        let active = log_dir.join(LOG_FILE_NAME);
        if active.exists() {
            let dst = log_dir.join(format!("{LOG_FILE_NAME}.1"));
            fs::rename(&active, &dst)?;
        }
    } else {
        let active = log_dir.join(LOG_FILE_NAME);
        if active.exists() {
            let _ = fs::remove_file(&active);
        }
    }
    Ok(())
}

enum OutletState {
    File { file: File, current_size: u64 },
    Memory { buffer: VecDeque<String> },
}

/// 诊断日志出口。
pub struct LogOutlet {
    log_dir: PathBuf,
    max_file_size: u64,
    max_old_files: usize,
    inner: Mutex<OutletState>,
}

impl LogOutlet {
    /// 以默认上限（5 MB 单文件、保留 5 份旧文件）创建日志出口。
    pub fn new(log_dir: PathBuf) -> Self {
        Self::new_with_limits(log_dir, DEFAULT_MAX_FILE_SIZE, DEFAULT_MAX_OLD_FILES)
    }

    /// 以指定单文件大小与保留份数创建日志出口。
    pub fn new_with_limits(log_dir: PathBuf, max_file_size: u64, max_old_files: usize) -> Self {
        if fs::create_dir_all(&log_dir).is_err() {
            return Self {
                log_dir,
                max_file_size,
                max_old_files,
                inner: Mutex::new(OutletState::Memory {
                    buffer: VecDeque::with_capacity(MEMORY_BUFFER_LIMIT),
                }),
            };
        }

        let active = log_dir.join(LOG_FILE_NAME);
        let existing_size = fs::metadata(&active).map(|m| m.len()).unwrap_or(0);

        if existing_size >= max_file_size && rotate_files(&log_dir, max_old_files).is_err() {
            return Self {
                log_dir,
                max_file_size,
                max_old_files,
                inner: Mutex::new(OutletState::Memory {
                    buffer: VecDeque::with_capacity(MEMORY_BUFFER_LIMIT),
                }),
            };
        }

        let open_res = OpenOptions::new().create(true).append(true).open(&active);

        match open_res {
            Ok(file) => {
                let size = fs::metadata(&active).map(|m| m.len()).unwrap_or(0);
                Self {
                    log_dir,
                    max_file_size,
                    max_old_files,
                    inner: Mutex::new(OutletState::File {
                        file,
                        current_size: size,
                    }),
                }
            }
            Err(_) => Self {
                log_dir,
                max_file_size,
                max_old_files,
                inner: Mutex::new(OutletState::Memory {
                    buffer: VecDeque::with_capacity(MEMORY_BUFFER_LIMIT),
                }),
            },
        }
    }

    pub fn log_dir(&self) -> &Path {
        &self.log_dir
    }

    pub fn log_file_path(&self) -> PathBuf {
        self.log_dir.join(LOG_FILE_NAME)
    }

    pub fn is_degraded(&self) -> bool {
        let state = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        matches!(*state, OutletState::Memory { .. })
    }

    pub fn memory_records(&self) -> Vec<String> {
        let state = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        match &*state {
            OutletState::Memory { buffer } => buffer.iter().cloned().collect(),
            OutletState::File { .. } => Vec::new(),
        }
    }

    pub fn write_line(&self, line: &str) {
        // 1. 写盘前切断 URL 查询参数，履行隐私政策承诺
        let redacted = crate::failure::redact_url_secrets(line);

        // 2. 将嵌入的换行符转义，保障单条记录在物理文件中占且仅占单行
        let sanitized = if redacted.contains('\n') || redacted.contains('\r') {
            redacted
                .replace("\r\n", "\\n")
                .replace('\n', "\\n")
                .replace('\r', "")
        } else {
            redacted
        };

        let mut state = self.inner.lock().unwrap_or_else(|e| e.into_inner());

        // 3. 内存降级自愈检测：若此前曾因只读或短暂文件锁降级，尝试重新连接文件并将缓冲排空落盘
        if let OutletState::Memory { buffer } = &mut *state {
            let active = self.log_dir.join(LOG_FILE_NAME);
            if fs::create_dir_all(&self.log_dir).is_ok() {
                if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&active) {
                    let mut current_size = fs::metadata(&active).map(|m| m.len()).unwrap_or(0);
                    let mut write_failed = false;
                    for old_line in buffer.drain(..) {
                        let add = old_line.len() as u64 + 1;
                        if file.write_all(old_line.as_bytes()).is_ok()
                            && file.write_all(b"\n").is_ok()
                        {
                            current_size += add;
                        } else {
                            write_failed = true;
                            break;
                        }
                    }
                    if !write_failed && file.flush().is_ok() {
                        *state = OutletState::File { file, current_size };
                    }
                }
            }
        }

        let add_len = sanitized.len() as u64 + 1; // 包含换行符

        let need_rotate = match &*state {
            OutletState::File { current_size, .. } => {
                *current_size + add_len > self.max_file_size && *current_size > 0
            }
            OutletState::Memory { .. } => false,
        };

        if need_rotate {
            // 先释放当前文件句柄以保证跨平台（Windows 锁文件）重命名安全
            *state = OutletState::Memory {
                buffer: VecDeque::with_capacity(MEMORY_BUFFER_LIMIT),
            };

            if rotate_files(&self.log_dir, self.max_old_files).is_ok() {
                let active = self.log_dir.join(LOG_FILE_NAME);
                if let Ok(file) = OpenOptions::new().create(true).append(true).open(&active) {
                    *state = OutletState::File {
                        file,
                        current_size: 0,
                    };
                }
            }
        }

        match &mut *state {
            OutletState::File { file, current_size } => {
                let mut ok = false;
                if file.write_all(sanitized.as_bytes()).is_ok()
                    && file.write_all(b"\n").is_ok()
                    && file.flush().is_ok()
                {
                    *current_size += add_len;
                    ok = true;
                }
                if !ok {
                    let mut buffer = VecDeque::with_capacity(MEMORY_BUFFER_LIMIT);
                    buffer.push_back(sanitized);
                    *state = OutletState::Memory { buffer };
                }
            }
            OutletState::Memory { buffer } => {
                if buffer.len() >= MEMORY_BUFFER_LIMIT {
                    buffer.pop_front();
                }
                buffer.push_back(sanitized);
            }
        }
    }

    /// 记录应用启动第一行诊断记录。
    pub fn record_startup(&self) {
        let timestamp = format_utc_timestamp(SystemTime::now());
        let version = env!("CARGO_PKG_VERSION");
        let os = std::env::consts::OS;
        let arch = std::env::consts::ARCH;
        let line =
            format!("[{timestamp}] [INFO] [app] startup version={version} os={os} arch={arch}");
        self.write_line(&line);
    }

    /// 清理所有日志文件（sodam.log 与所有轮转备份），供诊断清理功能使用。
    pub fn clear_logs(&self) -> std::io::Result<()> {
        let mut state = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        *state = OutletState::Memory {
            buffer: VecDeque::with_capacity(MEMORY_BUFFER_LIMIT),
        };
        let active = self.log_dir.join(LOG_FILE_NAME);
        if active.exists() {
            let _ = fs::remove_file(&active);
        }
        for i in 1..=self.max_old_files {
            let old = self.log_dir.join(format!("{LOG_FILE_NAME}.{i}"));
            if old.exists() {
                let _ = fs::remove_file(&old);
            }
        }
        if let Ok(file) = OpenOptions::new().create(true).append(true).open(&active) {
            *state = OutletState::File {
                file,
                current_size: 0,
            };
        }
        Ok(())
    }
}

static GLOBAL_OUTLET: OnceLock<LogOutlet> = OnceLock::new();

/// 初始化全局默认日志出口并记录启动首行记录。
pub fn init() -> &'static LogOutlet {
    init_with_dir(log_dir())
}

/// 使用指定日志目录初始化全局日志出口。
pub fn init_with_dir(dir: PathBuf) -> &'static LogOutlet {
    GLOBAL_OUTLET.get_or_init(|| {
        let outlet = LogOutlet::new(dir);
        outlet.record_startup();
        outlet
    })
}

/// 获取已初始化的全局日志出口引用。
pub fn global() -> Option<&'static LogOutlet> {
    GLOBAL_OUTLET.get()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_platform_path_resolution() {
        let base_win = Path::new("test_local_app_data");
        let win = resolve_platform_log_dir(Platform::Windows, Some(base_win), None, None, None);
        assert_eq!(win, base_win.join("sodam").join("logs"));

        let base_mac = Path::new("/Users/test/Library/Application Support");
        let mac = resolve_platform_log_dir(Platform::MacOS, None, None, Some(base_mac), None);
        assert_eq!(mac, base_mac.join("sodam").join("logs"));

        let base_state = Path::new("/home/test/.local/state");
        let linux_state =
            resolve_platform_log_dir(Platform::Linux, None, Some(base_state), None, None);
        assert_eq!(linux_state, base_state.join("sodam").join("logs"));

        let base_home = Path::new("/home/test");
        let linux_fallback =
            resolve_platform_log_dir(Platform::Linux, None, None, None, Some(base_home));
        assert_eq!(
            linux_fallback,
            base_home
                .join(".local")
                .join("state")
                .join("sodam")
                .join("logs")
        );
    }

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    struct EnvGuard<'a>(&'a str, Option<std::ffi::OsString>);
    impl<'a> Drop for EnvGuard<'a> {
        fn drop(&mut self) {
            if let Some(val) = &self.1 {
                std::env::set_var(self.0, val);
            } else {
                std::env::remove_var(self.0);
            }
        }
    }

    #[test]
    fn test_env_log_dir_override() {
        let _lock = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let orig = std::env::var_os("SODAM_LOG_DIR");
        let _guard = EnvGuard("SODAM_LOG_DIR", orig);

        let custom_dir = std::env::temp_dir().join("sodam_test_custom_logs");
        std::env::set_var("SODAM_LOG_DIR", &custom_dir);
        assert_eq!(log_dir(), custom_dir);
    }

    #[test]
    fn test_civil_from_days_and_timestamp() {
        // 1970-01-01 00:00:00 UTC
        let t0 = SystemTime::UNIX_EPOCH;
        assert_eq!(format_utc_timestamp(t0), "1970-01-01T00:00:00Z");

        // 2026-10-25 00:00:00 UTC (1792886400 / 86400 = 20751 days)
        let t_2026 = SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1792886400);
        assert_eq!(format_utc_timestamp(t_2026), "2026-10-25T00:00:00Z");
    }

    #[test]
    fn test_log_rotation_and_retention() {
        let temp = tempfile::tempdir().unwrap();
        let log_dir = temp.path().join("logs");

        // 阈值设为 40 字节，保留 3 份旧文件
        let outlet = LogOutlet::new_with_limits(log_dir.clone(), 40, 3);
        assert!(!outlet.is_degraded());

        // 写入 5 条记录（每条约 25 字节，每写两条就会触发一次轮转）
        for i in 1..=6 {
            outlet.write_line(&format!("line-{i:02}: 0123456789abcdef"));
        }

        let active = log_dir.join(LOG_FILE_NAME);
        assert!(active.exists(), "活跃文件 sodam.log 必须存在");

        let b1 = log_dir.join(format!("{LOG_FILE_NAME}.1"));
        let b2 = log_dir.join(format!("{LOG_FILE_NAME}.2"));
        let b3 = log_dir.join(format!("{LOG_FILE_NAME}.3"));
        let b4 = log_dir.join(format!("{LOG_FILE_NAME}.4"));

        assert!(b1.exists(), "旧文件 1 必须存在");
        assert!(b2.exists(), "旧文件 2 必须存在");
        assert!(b3.exists(), "旧文件 3 必须存在");
        assert!(!b4.exists(), "旧文件数量不能超过保留份数 3");
    }

    #[test]
    fn test_startup_record_written() {
        let temp = tempfile::tempdir().unwrap();
        let log_dir = temp.path().join("logs");

        let outlet = LogOutlet::new(log_dir.clone());
        outlet.record_startup();

        let log_file = log_dir.join(LOG_FILE_NAME);
        assert!(log_file.exists());
        let content = fs::read_to_string(&log_file).unwrap();
        assert!(content.contains("[INFO] [app] startup version="));
        assert!(content.contains("os="));
        assert!(content.contains("arch="));
    }

    #[test]
    fn test_unwritable_directory_memory_fallback() {
        let temp = tempfile::tempdir().unwrap();
        // 创建一个普通文件，然后尝试以其子路径作为日志目录（必定失败）
        let block_file = temp.path().join("blocked_path");
        fs::write(&block_file, b"cannot be a directory").unwrap();
        let impossible_dir = block_file.join("sub_logs");

        let outlet = LogOutlet::new(impossible_dir);
        assert!(outlet.is_degraded(), "不可写目录应降级到内存模式");

        outlet.write_line("fallback entry 1");
        outlet.write_line("fallback entry 2");

        let records = outlet.memory_records();
        assert_eq!(records.len(), 2);
        assert_eq!(records[0], "fallback entry 1");
        assert_eq!(records[1], "fallback entry 2");
    }

    #[test]
    fn test_clear_logs() {
        let temp = tempfile::tempdir().unwrap();
        let log_dir = temp.path().join("logs");

        let outlet = LogOutlet::new_with_limits(log_dir.clone(), 30, 2);
        outlet.write_line("entry-1: 0123456789abcdef");
        outlet.write_line("entry-2: 0123456789abcdef");
        outlet.write_line("entry-3: 0123456789abcdef");

        assert!(log_dir.join(format!("{LOG_FILE_NAME}.1")).exists());

        outlet.clear_logs().unwrap();
        assert!(!log_dir.join(format!("{LOG_FILE_NAME}.1")).exists());
        let active_content = fs::read_to_string(log_dir.join(LOG_FILE_NAME)).unwrap();
        assert!(active_content.is_empty());
    }

    #[test]
    fn test_write_line_redacts_url_secrets() {
        let temp = tempfile::tempdir().unwrap();
        let outlet = LogOutlet::new(temp.path().to_path_buf());
        outlet.write_line(
            "下载失败 https://api.example.com/audio?id=1&token=SECRET Cookie=session=abc",
        );

        let content = fs::read_to_string(outlet.log_file_path()).unwrap();
        assert!(content.contains("https://api.example.com/audio?…"));
        assert!(!content.contains("token=SECRET"));
    }

    #[test]
    fn test_write_line_escapes_embedded_newlines() {
        let temp = tempfile::tempdir().unwrap();
        let outlet = LogOutlet::new(temp.path().to_path_buf());
        outlet.write_line("first half\nsecond half\r\nthird");

        let content = fs::read_to_string(outlet.log_file_path()).unwrap();
        let lines: Vec<&str> = content.lines().collect();
        assert_eq!(lines.len(), 1, "嵌入换行必须转义在单行内");
        assert!(lines[0].contains(r"first half\nsecond half\nthird"));
    }

    #[test]
    fn test_memory_degradation_recovery() {
        let temp = tempfile::tempdir().unwrap();
        let block_file = temp.path().join("block");
        fs::write(&block_file, b"file").unwrap();
        let blocked_dir = block_file.join("sub");

        let outlet = LogOutlet::new(blocked_dir.clone());
        assert!(outlet.is_degraded());
        outlet.write_line("buffered 1");
        outlet.write_line("buffered 2");
        assert_eq!(outlet.memory_records().len(), 2);

        // 移除阻断文件，使目录恢复可写
        fs::remove_file(&block_file).unwrap();
        outlet.write_line("buffered 3");

        assert!(!outlet.is_degraded(), "写入恢复后应自愈退出内存降级");
        let content = fs::read_to_string(outlet.log_file_path()).unwrap();
        assert!(content.contains("buffered 1"));
        assert!(content.contains("buffered 2"));
        assert!(content.contains("buffered 3"));
    }
}
