use crate::app::Config;
use crate::disk;
use anyhow::{Context, Result};
use std::{
    fs,
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::mpsc,
    thread,
};

pub enum Msg {
    Log(String),
    NeedPasswords(Vec<String>),
    Done,
    Error(String),
}

pub fn start(
    config: Config,
    tx: mpsc::Sender<Msg>,
    dry_run: bool,
) -> mpsc::Sender<Vec<(String, String)>> {
    let (pw_tx, pw_rx) = mpsc::channel::<Vec<(String, String)>>();
    thread::spawn(move || {
        let result = if dry_run {
            run_dry(config, &tx, pw_rx)
        } else {
            run(config, &tx, pw_rx)
        };
        if let Err(e) = result {
            let _ = tx.send(Msg::Error(e.to_string()));
        }
    });
    pw_tx
}

fn run_dry(
    config: Config,
    tx: &mpsc::Sender<Msg>,
    pw_rx: mpsc::Receiver<Vec<(String, String)>>,
) -> Result<()> {
    use std::time::Duration;

    let steps: Vec<(u64, String)> = vec![
        (800, "DRY RUN — no real changes will be made".into()),
        (
            600,
            "Preflight: building target system before touching the disk (skipped)".into(),
        ),
        (600, "Preparing empty-space partition plan...".into()),
        (400, format!("  Disk:  {}", config.disk.name)),
        (400, format!("  Host:  {}", config.host)),
        (
            600,
            "Creating EFI and root partitions in selected free space (skipped)".into(),
        ),
        (600, "Formatting new EFI partition (skipped)".into()),
        (600, "Formatting LUKS2 partition (skipped)".into()),
        (600, "Formatting root filesystem (skipped)".into()),
        (600, "Mounting filesystems (skipped)".into()),
        (600, "Copying config (skipped)".into()),
        (
            1200,
            "Running nixos-install (skipped — would take several minutes)".into(),
        ),
        (600, "Fixing ownership (skipped)".into()),
    ];

    for (delay_ms, msg) in steps {
        let _ = tx.send(Msg::Log(msg));
        thread::sleep(Duration::from_millis(delay_ms));
    }

    let _ = tx.send(Msg::NeedPasswords(vec!["fabius".into(), "root".into()]));
    let passwords = pw_rx.recv().context("password channel closed")?;

    for (user, _) in &passwords {
        let _ = tx.send(Msg::Log(format!("Setting password for {} (skipped)", user)));
        thread::sleep(Duration::from_millis(400));
    }

    let _ = tx.send(Msg::Log("Done! (dry run — nothing was written)".into()));
    let _ = tx.send(Msg::Done);
    Ok(())
}

fn cmd_log(args: &[&str], tx: &mpsc::Sender<Msg>) -> Result<()> {
    let mut child = Command::new(args[0])
        .args(&args[1..])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("spawning {}", args[0]))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();
    let tx2 = tx.clone();

    let stderr_thread = thread::spawn(move || {
        for line in BufReader::new(stderr).lines().map_while(Result::ok) {
            let _ = tx2.send(Msg::Log(line));
        }
    });

    for line in BufReader::new(stdout).lines().map_while(Result::ok) {
        let _ = tx.send(Msg::Log(line));
    }

    stderr_thread.join().ok();

    let status = child.wait().context("waiting for child")?;
    if !status.success() {
        anyhow::bail!("{} failed with {}", args[0], status);
    }
    Ok(())
}

fn cmd_stdin(args: &[&str], input: &str) -> Result<()> {
    let mut child = Command::new(args[0])
        .args(&args[1..])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .with_context(|| format!("spawning {}", args[0]))?;

    if let Some(mut stdin) = child.stdin.take() {
        writeln!(stdin, "{}", input)?;
    }

    let status = child.wait().context("waiting for child")?;
    if !status.success() {
        anyhow::bail!("{} failed with {}", args[0], status);
    }
    Ok(())
}

fn run(
    config: Config,
    tx: &mpsc::Sender<Msg>,
    pw_rx: mpsc::Receiver<Vec<(String, String)>>,
) -> Result<()> {
    let plan = config
        .partition_plan
        .as_ref()
        .context("no partition plan")?;

    let _ = tx.send(Msg::Log(format!(
        "Preflight: evaluating target config for {} before touching the disk...",
        config.host
    )));
    // nix eval forces full config evaluation (catches unfree, bad packages, option errors)
    // without downloading anything into the live tmpfs store.
    // nixos-install later downloads everything to /mnt/nix/store on the target disk.
    let target_attr = format!(
        "{}#nixosConfigurations.{}.config.system.build.toplevel.outPath",
        config.config_path, config.host
    );
    cmd_log(
        &["nix", "eval", "--raw", "--no-write-lock-file", &target_attr],
        tx,
    )?;

    let _ = tx.send(Msg::Log(format!(
        "Creating new partitions in empty space on {}...",
        config.disk.path.display()
    )));
    let _ = tx.send(Msg::Log(format!(
        "  EFI:  LBA {}-{} ({})",
        plan.boot.first_lba,
        plan.boot.last_lba,
        disk::format_bytes(plan.boot.size_bytes)
    )));
    let _ = tx.send(Msg::Log(format!(
        "  Root: LBA {}-{} ({})",
        plan.root.first_lba,
        plan.root.last_lba,
        disk::format_bytes(plan.root.size_bytes)
    )));

    let (boot_part, root_part): (PathBuf, PathBuf) =
        disk::create_partitions_from_plan(&config.disk, plan)?;

    let _ = tx.send(Msg::Log(format!(
        "Formatting new EFI partition {}...",
        boot_part.display()
    )));
    cmd_log(
        &[
            "mkfs.fat",
            "-F",
            "32",
            "-n",
            "BOOT",
            boot_part.to_str().unwrap(),
        ],
        tx,
    )?;

    let _ = tx.send(Msg::Log(format!(
        "Formatting LUKS2 partition {}...",
        root_part.display()
    )));
    cmd_stdin(
        &[
            "cryptsetup",
            "luksFormat",
            "--type",
            "luks2",
            "--cipher",
            "aes-xts-plain64",
            "--key-size",
            "512",
            "--hash",
            "sha256",
            "--pbkdf",
            "argon2id",
            "--pbkdf-memory",
            "1048576",
            "--pbkdf-parallel",
            "4",
            "--iter-time",
            "3000",
            "--batch-mode",
            root_part.to_str().unwrap(),
        ],
        &config.passphrase,
    )?;

    let _ = tx.send(Msg::Log(
        "Opening encrypted partition as /dev/mapper/cryptroot...".into(),
    ));
    cmd_stdin(
        &[
            "cryptsetup",
            "open",
            root_part.to_str().unwrap(),
            "cryptroot",
        ],
        &config.passphrase,
    )?;

    let fs_device = PathBuf::from("/dev/mapper/cryptroot");

    let _ = tx.send(Msg::Log(format!(
        "Formatting root filesystem {}...",
        fs_device.display()
    )));
    cmd_log(
        &["mkfs.ext4", "-L", "nixos", fs_device.to_str().unwrap()],
        tx,
    )?;

    let _ = tx.send(Msg::Log("Mounting filesystems...".into()));
    cmd_log(&["mount", fs_device.to_str().unwrap(), "/mnt"], tx)?;
    fs::create_dir_all("/mnt/boot").context("creating /mnt/boot")?;
    cmd_log(
        &[
            "mount",
            "-o",
            "umask=077",
            boot_part.to_str().unwrap(),
            "/mnt/boot",
        ],
        tx,
    )?;

    let _ = tx.send(Msg::Log("Copying config...".into()));
    fs::create_dir_all("/mnt/etc").context("creating /mnt/etc")?;
    copy_recursively(Path::new(&config.config_path), Path::new("/mnt/etc/nixos"))
        .context("copying config to /mnt/etc/nixos")?;

    let _ = tx.send(Msg::Log(
        "Running nixos-install (this takes a while)...".into(),
    ));
    let flake_arg = format!("/mnt/etc/nixos#{}", config.host);
    cmd_log(
        &["nixos-install", "--no-root-passwd", "--flake", &flake_arg],
        tx,
    )?;

    let _ = tx.send(Msg::Log("Fixing ownership...".into()));
    if let Some(home) = first_home_dir(Path::new("/mnt/home"))? {
        let home_arg = home.to_string_lossy().to_string();
        cmd_log(&["chown", "-R", "1000:1000", &home_arg], tx)?;
    }

    let users = users_from_passwd(Path::new("/mnt/etc/passwd"))?;

    let _ = tx.send(Msg::NeedPasswords(users));

    let passwords = pw_rx.recv().context("password channel closed")?;

    for (user, password) in &passwords {
        let _ = tx.send(Msg::Log(format!("Setting password for {}...", user)));
        cmd_stdin(
            &["nixos-enter", "--root", "/mnt", "-c", "chpasswd"],
            &format!("{}:{}", user, password),
        )?;
    }

    let _ = tx.send(Msg::Done);
    Ok(())
}

fn copy_recursively(src: &Path, dest: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(src)?;
    if metadata.file_type().is_symlink() {
        let target = fs::read_link(src)?;
        #[cfg(unix)]
        std::os::unix::fs::symlink(target, dest)?;
        #[cfg(not(unix))]
        fs::copy(src, dest)?;
    } else if metadata.is_dir() {
        fs::create_dir_all(dest)?;
        for entry in fs::read_dir(src)? {
            let entry = entry?;
            copy_recursively(&entry.path(), &dest.join(entry.file_name()))?;
        }
    } else {
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::copy(src, dest)?;
    }
    Ok(())
}

fn first_home_dir(home_root: &Path) -> Result<Option<PathBuf>> {
    if !home_root.exists() {
        return Ok(None);
    }
    for entry in fs::read_dir(home_root)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            return Ok(Some(entry.path()));
        }
    }
    Ok(None)
}

fn users_from_passwd(path: &Path) -> Result<Vec<String>> {
    let passwd = fs::read_to_string(path).context("reading installed /etc/passwd")?;
    Ok(passwd
        .lines()
        .filter_map(|line| {
            let mut fields = line.split(':');
            let name = fields.next()?;
            let _password = fields.next()?;
            let uid = fields.next()?.parse::<u32>().ok()?;
            let _gid = fields.next()?;
            let _gecos = fields.next()?;
            let home = fields.next()?;
            // Only real human users: UID 1000-1999 with a home under /home
            ((1000..2000).contains(&uid) && home.starts_with("/home/")).then(|| name.to_string())
        })
        .collect())
}
