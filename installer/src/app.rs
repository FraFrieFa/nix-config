use crate::{
    disk::{Disk, FreeExtent, PartitionPlan},
    install,
};
use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use std::{
    env, fs, mem,
    net::{TcpStream, ToSocketAddrs},
    path::{Path, PathBuf},
    process::Command,
    sync::mpsc,
    thread,
    time::Duration,
};

type HostsResult = Result<(Vec<String>, String, ConfigSource), String>;

#[derive(Clone)]
pub struct Config {
    pub host: String,
    pub disk: Disk,
    pub root_extent: Option<FreeExtent>,
    pub partition_plan: Option<PartitionPlan>,
    pub passphrase: String,
    pub overprovision_pct: u8,
    pub config_path: String,
    pub config_source: ConfigSource,
}

#[derive(Clone)]
pub enum ConfigSource {
    EmbeddedOffline,
    PulledFromGit,
}

#[derive(Clone)]
pub struct NetworkStatus {
    pub checking: bool,
    pub online: bool,
    pub git_available: bool,
    pub message: String,
}

pub enum Screen {
    ConfigSource {
        selected: usize,
        network: NetworkStatus,
    },
    LoadingHosts,
    HostSelect {
        hosts: Vec<String>,
        selected: usize,
    },
    DiskSelect {
        disks: Vec<Disk>,
        selected: usize,
    },
    FreeSpaceSelect {
        extents: Vec<FreeExtent>,
        selected: usize,
    },
    Passphrase {
        input: String,
        confirm: String,
        focused: usize,
        mismatch: bool,
    },
    OverprovisionChoice {
        selected: usize,
        is_ssd: bool,
    },
    Summary,
    Installing {
        log: Vec<String>,
        scroll: usize,
    },
    SetPasswords {
        users: Vec<String>,
        collected: Vec<String>,
        input: String,
        confirm: String,
        focused: usize,
        mismatch: bool,
    },
    Done,
    Error(String),
}

pub struct App {
    pub screen: Screen,
    pub config: Config,
    pub should_quit: bool,
    pub install_rx: Option<mpsc::Receiver<install::Msg>>,
    pub password_tx: Option<mpsc::Sender<Vec<(String, String)>>>,
    pub install_done: bool,
    pub install_error: bool,
    pub dry_run: bool,
    pub network_rx: Option<mpsc::Receiver<NetworkStatus>>,
    pub hosts_rx: Option<mpsc::Receiver<HostsResult>>,
    pub cached_hosts: Vec<String>,
    pub tick: usize,
}

impl App {
    pub fn new(dry_run: bool) -> Self {
        let dummy_disk = Disk {
            name: String::new(),
            path: PathBuf::new(),
            size_bytes: 0,
            model: String::new(),
        };
        let (network, network_rx) = Self::start_network_check();
        let selected = 1;
        Self {
            screen: Screen::ConfigSource { selected, network },
            config: Config {
                host: String::new(),
                disk: dummy_disk,
                root_extent: None,
                partition_plan: None,
                passphrase: String::new(),
                overprovision_pct: 0,
                config_path: "/etc/nix-config".into(),
                config_source: ConfigSource::EmbeddedOffline,
            },
            should_quit: false,
            install_rx: None,
            password_tx: None,
            install_done: false,
            install_error: false,
            dry_run,
            network_rx: Some(network_rx),
            hosts_rx: None,
            cached_hosts: Vec::new(),
            tick: 0,
        }
    }

    pub fn tick(&mut self) {
        self.tick = self.tick.wrapping_add(1);
        self.poll_network_status();
        self.poll_hosts();
    }

    fn poll_network_status(&mut self) {
        let rx = match self.network_rx.as_ref() {
            Some(r) => r,
            None => return,
        };

        match rx.try_recv() {
            Ok(network) => {
                if let Screen::ConfigSource {
                    selected,
                    network: current,
                } = &mut self.screen
                {
                    *current = network.clone();
                    if network.online && network.git_available && *selected == 1 {
                        *selected = 0;
                    }
                }
                self.network_rx = None;
            }
            Err(mpsc::TryRecvError::Empty) => {}
            Err(mpsc::TryRecvError::Disconnected) => {
                self.network_rx = None;
            }
        }
    }

    fn poll_hosts(&mut self) {
        let rx = match self.hosts_rx.as_ref() {
            Some(r) => r,
            None => return,
        };
        match rx.try_recv() {
            Ok(Ok((hosts, config_path, config_source))) => {
                self.hosts_rx = None;
                self.config.config_path = config_path;
                self.config.config_source = config_source;
                self.cached_hosts = hosts.clone();
                self.screen = Screen::HostSelect { hosts, selected: 0 };
            }
            Ok(Err(e)) => {
                self.hosts_rx = None;
                self.screen = Screen::Error(e);
            }
            Err(mpsc::TryRecvError::Empty) => {}
            Err(mpsc::TryRecvError::Disconnected) => {
                self.hosts_rx = None;
                self.screen = Screen::Error("Configuration loading failed unexpectedly".into());
            }
        }
    }

    pub fn poll_install_messages(&mut self) {
        let rx = match self.install_rx.as_ref() {
            Some(r) => r,
            None => return,
        };

        loop {
            match rx.try_recv() {
                Ok(install::Msg::Log(s)) => {
                    if let Screen::Installing {
                        ref mut log,
                        ref mut scroll,
                    } = self.screen
                    {
                        log.push(s);
                        *scroll = log.len().saturating_sub(1);
                    }
                }
                Ok(install::Msg::NeedPasswords(users)) => {
                    self.screen = Screen::SetPasswords {
                        users,
                        collected: Vec::new(),
                        input: String::new(),
                        confirm: String::new(),
                        focused: 0,
                        mismatch: false,
                    };
                    break;
                }
                Ok(install::Msg::Done) => {
                    self.install_done = true;
                    self.screen = Screen::Done;
                    break;
                }
                Ok(install::Msg::Error(e)) => {
                    self.install_error = true;
                    if let Screen::Installing {
                        ref mut log,
                        ref mut scroll,
                    } = self.screen
                    {
                        log.push(format!("ERROR: {}", e));
                        *scroll = log.len().saturating_sub(1);
                    } else {
                        self.screen = Screen::Error(e);
                    }
                    break;
                }
                Err(_) => break,
            }
        }
    }

    pub fn handle_key(&mut self, key: KeyEvent) {
        if key.kind != KeyEventKind::Press {
            return;
        }
        let screen = mem::replace(&mut self.screen, Screen::Done);
        self.screen = self.process(screen, key);
    }

    fn process(&mut self, screen: Screen, key: KeyEvent) -> Screen {
        match screen {
            Screen::ConfigSource {
                mut selected,
                network,
            } => match key.code {
                KeyCode::Up | KeyCode::Char('k') => {
                    if network.online && network.git_available && selected > 0 {
                        selected -= 1;
                    }
                    Screen::ConfigSource { selected, network }
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    if selected < 1 {
                        selected += 1;
                    }
                    Screen::ConfigSource { selected, network }
                }
                KeyCode::Enter => {
                    let pull_from_git = selected == 0;
                    if pull_from_git && (!network.online || !network.git_available) {
                        return Screen::ConfigSource { selected, network };
                    }
                    self.spawn_hosts_load(pull_from_git)
                }
                _ => Screen::ConfigSource { selected, network },
            },

            Screen::LoadingHosts => match key.code {
                KeyCode::Esc => {
                    self.hosts_rx = None;
                    let (network, rx) = Self::start_network_check();
                    let selected = if network.online && network.git_available {
                        0
                    } else {
                        1
                    };
                    self.network_rx = Some(rx);
                    Screen::ConfigSource { selected, network }
                }
                _ => Screen::LoadingHosts,
            },

            Screen::HostSelect {
                hosts,
                mut selected,
            } => match key.code {
                KeyCode::Up | KeyCode::Char('k') => {
                    if selected > 0 {
                        selected -= 1;
                    }
                    Screen::HostSelect { hosts, selected }
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    if selected + 1 < hosts.len() {
                        selected += 1;
                    }
                    Screen::HostSelect { hosts, selected }
                }
                KeyCode::Enter => {
                    if !hosts.is_empty() {
                        self.config.host = hosts[selected].clone();
                        self.load_disks()
                    } else {
                        Screen::HostSelect { hosts, selected }
                    }
                }
                KeyCode::Esc => {
                    let (network, rx) = Self::start_network_check();
                    let selected = if network.online && network.git_available {
                        0
                    } else {
                        1
                    };
                    self.network_rx = Some(rx);
                    Screen::ConfigSource { selected, network }
                }
                _ => Screen::HostSelect { hosts, selected },
            },

            Screen::DiskSelect {
                disks,
                mut selected,
            } => match key.code {
                KeyCode::Up | KeyCode::Char('k') => {
                    if selected > 0 {
                        selected -= 1;
                    }
                    Screen::DiskSelect { disks, selected }
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    if selected + 1 < disks.len() {
                        selected += 1;
                    }
                    Screen::DiskSelect { disks, selected }
                }
                KeyCode::Enter => {
                    if !disks.is_empty() {
                        self.config.disk = disks[selected].clone();
                        self.load_free_space()
                    } else {
                        Screen::DiskSelect { disks, selected }
                    }
                }
                KeyCode::Esc => {
                    if !self.cached_hosts.is_empty() {
                        Screen::HostSelect {
                            hosts: self.cached_hosts.clone(),
                            selected: 0,
                        }
                    } else {
                        self.spawn_hosts_load(false)
                    }
                }
                _ => Screen::DiskSelect { disks, selected },
            },

            Screen::FreeSpaceSelect {
                extents,
                mut selected,
            } => match key.code {
                KeyCode::Up | KeyCode::Char('k') => {
                    if selected > 0 {
                        selected -= 1;
                    }
                    Screen::FreeSpaceSelect { extents, selected }
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    if selected + 1 < extents.len() {
                        selected += 1;
                    }
                    Screen::FreeSpaceSelect { extents, selected }
                }
                KeyCode::Enter => {
                    if !extents.is_empty() {
                        self.config.root_extent = Some(extents[selected].clone());
                        Screen::Passphrase {
                            input: String::new(),
                            confirm: String::new(),
                            focused: 0,
                            mismatch: false,
                        }
                    } else {
                        Screen::FreeSpaceSelect { extents, selected }
                    }
                }
                KeyCode::Esc => self.load_disks(),
                _ => Screen::FreeSpaceSelect { extents, selected },
            },

            Screen::Passphrase {
                mut input,
                mut confirm,
                mut focused,
                mut mismatch,
            } => match key.code {
                KeyCode::Tab => {
                    focused = if focused == 0 { 1 } else { 0 };
                    Screen::Passphrase {
                        input,
                        confirm,
                        focused,
                        mismatch,
                    }
                }
                KeyCode::Char(c) => {
                    if !key
                        .modifiers
                        .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT)
                    {
                        mismatch = false;
                        if focused == 0 {
                            input.push(c);
                        } else {
                            confirm.push(c);
                        }
                    }
                    Screen::Passphrase {
                        input,
                        confirm,
                        focused,
                        mismatch,
                    }
                }
                KeyCode::Backspace => {
                    if focused == 0 {
                        input.pop();
                    } else {
                        confirm.pop();
                    }
                    Screen::Passphrase {
                        input,
                        confirm,
                        focused,
                        mismatch,
                    }
                }
                KeyCode::Enter => {
                    if focused == 0 {
                        Screen::Passphrase {
                            input,
                            confirm,
                            focused: 1,
                            mismatch,
                        }
                    } else if input == confirm && !input.is_empty() {
                        self.config.passphrase = input;
                        let is_ssd = crate::disk::is_ssd(&self.config.disk);
                        Screen::OverprovisionChoice {
                            selected: 0,
                            is_ssd,
                        }
                    } else {
                        Screen::Passphrase {
                            input: String::new(),
                            confirm: String::new(),
                            focused: 0,
                            mismatch: true,
                        }
                    }
                }
                KeyCode::Esc => self.load_free_space(),
                _ => Screen::Passphrase {
                    input,
                    confirm,
                    focused,
                    mismatch,
                },
            },

            Screen::OverprovisionChoice {
                mut selected,
                is_ssd,
            } => match key.code {
                KeyCode::Up | KeyCode::Char('k') => {
                    if selected > 0 {
                        selected -= 1;
                    }
                    Screen::OverprovisionChoice { selected, is_ssd }
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    if selected < 3 {
                        selected += 1;
                    }
                    Screen::OverprovisionChoice { selected, is_ssd }
                }
                KeyCode::Enter => {
                    self.config.overprovision_pct = [0u8, 7, 10, 20][selected];
                    match self.build_partition_plan() {
                        Ok(()) => Screen::Summary,
                        Err(e) => Screen::Error(e),
                    }
                }
                KeyCode::Esc => Screen::Passphrase {
                    input: String::new(),
                    confirm: String::new(),
                    focused: 0,
                    mismatch: false,
                },
                _ => Screen::OverprovisionChoice { selected, is_ssd },
            },

            Screen::Summary => match key.code {
                KeyCode::Enter | KeyCode::Char('y') => self.begin_install(),
                KeyCode::Esc => {
                    let is_ssd = crate::disk::is_ssd(&self.config.disk);
                    Screen::OverprovisionChoice {
                        selected: 0,
                        is_ssd,
                    }
                }
                _ => Screen::Summary,
            },

            Screen::Installing { log, mut scroll } => match key.code {
                KeyCode::Up | KeyCode::Char('k') => {
                    if scroll > 0 {
                        scroll -= 1;
                    }
                    Screen::Installing { log, scroll }
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    if scroll + 1 < log.len() {
                        scroll += 1;
                    }
                    Screen::Installing { log, scroll }
                }
                KeyCode::Char('q') | KeyCode::Enter => {
                    if self.install_done || self.install_error {
                        self.should_quit = true;
                    }
                    Screen::Installing { log, scroll }
                }
                _ => Screen::Installing { log, scroll },
            },

            Screen::SetPasswords {
                users,
                mut collected,
                mut input,
                mut confirm,
                mut focused,
                mut mismatch,
            } => match key.code {
                KeyCode::Tab => {
                    focused = if focused == 0 { 1 } else { 0 };
                    Screen::SetPasswords {
                        users,
                        collected,
                        input,
                        confirm,
                        focused,
                        mismatch,
                    }
                }
                KeyCode::Char(c) => {
                    if !key
                        .modifiers
                        .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT)
                    {
                        mismatch = false;
                        if focused == 0 {
                            input.push(c);
                        } else {
                            confirm.push(c);
                        }
                    }
                    Screen::SetPasswords {
                        users,
                        collected,
                        input,
                        confirm,
                        focused,
                        mismatch,
                    }
                }
                KeyCode::Backspace => {
                    if focused == 0 {
                        input.pop();
                    } else {
                        confirm.pop();
                    }
                    Screen::SetPasswords {
                        users,
                        collected,
                        input,
                        confirm,
                        focused,
                        mismatch,
                    }
                }
                KeyCode::Enter => {
                    if focused == 0 {
                        Screen::SetPasswords {
                            users,
                            collected,
                            input,
                            confirm,
                            focused: 1,
                            mismatch,
                        }
                    } else if input == confirm {
                        collected.push(input);
                        let idx = collected.len();
                        if idx >= users.len() {
                            let passwords: Vec<(String, String)> =
                                users.into_iter().zip(collected.into_iter()).collect();
                            if let Some(tx) = self.password_tx.take() {
                                let _ = tx.send(passwords);
                            }
                            Screen::Installing {
                                log: vec!["Setting passwords...".into()],
                                scroll: 0,
                            }
                        } else {
                            Screen::SetPasswords {
                                users,
                                collected,
                                input: String::new(),
                                confirm: String::new(),
                                focused: 0,
                                mismatch: false,
                            }
                        }
                    } else {
                        Screen::SetPasswords {
                            users,
                            collected,
                            input: String::new(),
                            confirm: String::new(),
                            focused: 0,
                            mismatch: true,
                        }
                    }
                }
                KeyCode::Esc => Screen::Summary,
                _ => Screen::SetPasswords {
                    users,
                    collected,
                    input,
                    confirm,
                    focused,
                    mismatch,
                },
            },

            Screen::Done => {
                self.should_quit = true;
                Screen::Done
            }

            Screen::Error(_) => match key.code {
                KeyCode::Char('q') | KeyCode::Enter => {
                    self.should_quit = true;
                    screen
                }
                _ => screen,
            },
        }
    }

    fn spawn_hosts_load(&mut self, pull_from_git: bool) -> Screen {
        let dry_run = self.dry_run;
        let (tx, rx) = mpsc::channel::<HostsResult>();
        self.hosts_rx = Some(rx);
        thread::spawn(move || {
            let _ = tx.send(load_hosts_worker(pull_from_git, dry_run));
        });
        Screen::LoadingHosts
    }

    fn load_disks(&self) -> Screen {
        if self.dry_run {
            return Screen::DiskSelect {
                disks: vec![
                    crate::disk::Disk {
                        name: "sda".into(),
                        path: "/dev/sda".into(),
                        size_bytes: 512 * 1024 * 1024 * 1024,
                        model: "FAKE SSD 512G".into(),
                    },
                    crate::disk::Disk {
                        name: "nvme0n1".into(),
                        path: "/dev/nvme0n1".into(),
                        size_bytes: 1024 * 1024 * 1024 * 1024,
                        model: "FAKE NVMe 1T".into(),
                    },
                ],
                selected: 0,
            };
        }
        match crate::disk::enumerate_disks() {
            Ok(disks) if disks.is_empty() => Screen::Error("No disks found".into()),
            Ok(disks) => Screen::DiskSelect { disks, selected: 0 },
            Err(e) => Screen::Error(format!("enumerate disks: {}", e)),
        }
    }

    fn load_free_space(&self) -> Screen {
        if self.dry_run {
            return Screen::FreeSpaceSelect {
                extents: vec![crate::disk::FreeExtent {
                    start_lba: 2048,
                    end_lba: 419430400,
                    size_bytes: 200 * 1024 * 1024 * 1024,
                }],
                selected: 0,
            };
        }
        match crate::disk::find_free_extents(&self.config.disk) {
            Ok(extents) if extents.is_empty() => Screen::Error(format!(
                "No free space large enough for a new boot partition ({}) and root partition ({})",
                crate::disk::format_bytes(crate::disk::BOOT_BYTES),
                crate::disk::format_bytes(crate::disk::MIN_ROOT_BYTES),
            )),
            Ok(extents) => Screen::FreeSpaceSelect {
                extents,
                selected: 0,
            },
            Err(e) => Screen::Error(format!("find free extents: {}", e)),
        }
    }

    fn begin_install(&mut self) -> Screen {
        let (tx, rx) = mpsc::channel();
        self.install_rx = Some(rx);
        let pw_tx = install::start(self.config.clone(), tx, self.dry_run);
        self.password_tx = Some(pw_tx);
        Screen::Installing {
            log: vec!["Starting...".into()],
            scroll: 0,
        }
    }

    fn build_partition_plan(&mut self) -> Result<(), String> {
        let extent = self
            .config
            .root_extent
            .as_ref()
            .ok_or_else(|| "No free-space region selected".to_string())?;
        let plan = crate::disk::plan_empty_space(extent, self.config.overprovision_pct)
            .map_err(|e| format!("partition plan: {}", e))?;
        self.config.partition_plan = Some(plan);
        Ok(())
    }

    fn checking_network_status() -> NetworkStatus {
        NetworkStatus {
            checking: true,
            online: false,
            git_available: false,
            message: "Checking internet connection...".to_string(),
        }
    }

    fn start_network_check() -> (NetworkStatus, mpsc::Receiver<NetworkStatus>) {
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            let _ = tx.send(Self::network_status());
        });
        (Self::checking_network_status(), rx)
    }

    fn network_status() -> NetworkStatus {
        let git_available = command_available("git");
        let has_remote = fs::read_to_string("/etc/nix-config-url")
            .map(|s| !s.trim().is_empty())
            .unwrap_or(false);
        let online = has_remote && github_reachable();

        let message = if !has_remote {
            "No GitHub remote configured; using embedded config only".to_string()
        } else {
            match (online, git_available) {
                (true, true) => "Online; GitHub pull is available".to_string(),
                (true, false) => "Online, but git is not installed".to_string(),
                (false, true) => "Offline; using embedded config only".to_string(),
                (false, false) => {
                    "Offline and git is not installed; using embedded config only".to_string()
                }
            }
        };

        NetworkStatus {
            checking: false,
            online,
            git_available,
            message,
        }
    }
}

fn load_hosts_worker(pull_from_git: bool, dry_run: bool) -> HostsResult {
    let (config_path, config_source) = if dry_run {
        let path = find_flake_root().ok_or_else(|| {
            "dry-run: could not find flake.nix (run from inside the repo)".to_string()
        })?;
        (path, ConfigSource::EmbeddedOffline)
    } else if pull_from_git {
        let path = pull_config_from_git()?;
        (path, ConfigSource::PulledFromGit)
    } else {
        ("/etc/nix-config".to_string(), ConfigSource::EmbeddedOffline)
    };

    let hosts_dir = Path::new(&config_path).join("hosts");
    let mut hosts: Vec<String> = fs::read_dir(&hosts_dir)
        .map_err(|e| format!("reading {}: {}", hosts_dir.display(), e))?
        .flatten()
        .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    hosts.sort();

    if hosts.is_empty() {
        Err(format!("No hosts found in {}", hosts_dir.display()))
    } else {
        Ok((hosts, config_path, config_source))
    }
}

fn pull_config_from_git() -> Result<String, String> {
    let raw = fs::read_to_string("/etc/nix-config-url").unwrap_or_default();
    let remote_url = raw.trim();

    if remote_url.is_empty() {
        return Err("No remote URL found in /etc/nix-config-url.\n\
             Build the ISO from a GitHub-hosted flake to enable this feature."
            .into());
    }

    // Convert nix flake URL (e.g. "github:alice/nix-config") to HTTPS git URL
    let git_url = if let Some(repo) = remote_url.strip_prefix("github:") {
        let repo_slug: String = repo.splitn(3, '/').take(2).collect::<Vec<_>>().join("/");
        format!("https://github.com/{}", repo_slug)
    } else if remote_url.starts_with("git+file://") || remote_url.starts_with("path:") {
        return Err(
            "Cannot pull: the ISO was built from a local source, not a remote repository.\n\
             Push your config to GitHub and build the ISO from there."
                .into(),
        );
    } else {
        remote_url.to_string()
    };

    let dest = "/tmp/nix-config";
    if Path::new(dest).exists() {
        fs::remove_dir_all(dest).map_err(|e| format!("remove old config: {}", e))?;
    }

    let status = Command::new("git")
        .args(["clone", "--depth=1", &git_url, dest])
        .status()
        .map_err(|e| format!("git clone: {}", e))?;

    if !status.success() {
        return Err(format!(
            "Could not clone config from {}.\nCheck your network connection.",
            git_url
        ));
    }

    Ok(dest.to_string())
}

fn github_reachable() -> bool {
    let addrs = match ("github.com", 443).to_socket_addrs() {
        Ok(addrs) => addrs,
        Err(_) => return false,
    };

    addrs
        .into_iter()
        .any(|addr| TcpStream::connect_timeout(&addr, Duration::from_secs(3)).is_ok())
}

fn find_flake_root() -> Option<String> {
    let mut dir = env::current_dir().ok()?;
    loop {
        if dir.join("flake.nix").exists() {
            return Some(dir.to_string_lossy().to_string());
        }
        if !dir.pop() {
            return None;
        }
    }
}

fn command_available(name: &str) -> bool {
    let Some(paths) = env::var_os("PATH") else {
        return false;
    };
    env::split_paths(&paths).any(|dir| {
        fs::metadata(dir.join(name))
            .map(|metadata| metadata.is_file())
            .unwrap_or(false)
    })
}
