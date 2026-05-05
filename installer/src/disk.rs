use anyhow::{Context, Result};
use gpt::{disk::LogicalBlockSize, GptConfig};
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    thread,
    time::Duration,
};

#[derive(Clone, Debug)]
pub struct Disk {
    pub name: String,
    pub path: PathBuf,
    pub size_bytes: u64,
    pub model: String,
}

impl Disk {
    pub fn part_path(&self, n: u32) -> PathBuf {
        if self.name.contains("nvme") || self.name.contains("mmcblk") {
            PathBuf::from(format!("/dev/{}p{}", self.name, n))
        } else {
            PathBuf::from(format!("/dev/{}{}", self.name, n))
        }
    }
}

#[derive(Clone, Debug)]
pub struct FreeExtent {
    pub start_lba: u64,
    pub end_lba: u64,
    pub size_bytes: u64,
}

#[derive(Clone, Debug)]
pub struct PlannedPartition {
    pub name: String,
    pub part_type: PlannedPartitionType,
    pub first_lba: u64,
    pub last_lba: u64,
    pub size_bytes: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PlannedPartitionType {
    Efi,
    LinuxRoot,
}

#[derive(Clone, Debug)]
pub struct PartitionPlan {
    pub extent: FreeExtent,
    pub boot: PlannedPartition,
    pub root: PlannedPartition,
    pub overprovision_bytes: u64,
}

pub const BOOT_BYTES: u64 = 1024 * 1024 * 1024;
pub const MIN_ROOT_BYTES: u64 = 16 * 1024 * 1024 * 1024;
const SECTOR_BYTES: u64 = 512;
const ALIGN_SECTORS: u64 = 2048;

pub fn format_bytes(bytes: u64) -> String {
    let gib = bytes as f64 / (1024.0 * 1024.0 * 1024.0);
    if gib >= 1.0 {
        format!("{:.1} GiB", gib)
    } else {
        let mib = bytes as f64 / (1024.0 * 1024.0);
        format!("{:.0} MiB", mib)
    }
}

fn align_up(lba: u64) -> u64 {
    lba.div_ceil(ALIGN_SECTORS) * ALIGN_SECTORS
}

fn align_down(lba: u64) -> u64 {
    (lba / ALIGN_SECTORS) * ALIGN_SECTORS - 1
}

fn sectors_to_bytes(first_lba: u64, last_lba: u64) -> u64 {
    (last_lba - first_lba + 1) * SECTOR_BYTES
}

pub fn enumerate_disks() -> Result<Vec<Disk>> {
    let mut disks = Vec::new();
    let block_dir = Path::new("/sys/class/block");

    for entry in fs::read_dir(block_dir).context("reading /sys/class/block")? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().to_string();

        if name.starts_with("loop")
            || name.starts_with("ram")
            || name.starts_with("zram")
            || name.starts_with("sr")
            || name.starts_with("fd")
        {
            continue;
        }

        let base = block_dir.join(&name);
        if base.join("partition").exists() {
            continue;
        }

        let size_str = fs::read_to_string(base.join("size")).unwrap_or_default();
        let sectors: u64 = size_str.trim().parse().unwrap_or(0);
        let size_bytes = sectors * 512;

        if size_bytes == 0 {
            continue;
        }

        let model = fs::read_to_string(base.join("device/model"))
            .unwrap_or_default()
            .trim()
            .to_string();

        disks.push(Disk {
            path: PathBuf::from(format!("/dev/{}", name)),
            name,
            size_bytes,
            model,
        });
    }

    disks.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(disks)
}

pub fn find_free_extents(disk: &Disk) -> Result<Vec<FreeExtent>> {
    let gd = match GptConfig::new()
        .writable(false)
        .logical_block_size(LogicalBlockSize::Lb512)
        .open(&disk.path)
    {
        Ok(gd) => gd,
        Err(_) => {
            // No GPT — treat the whole disk as free space
            let total_sectors = disk.size_bytes / SECTOR_BYTES;
            let first_usable = ALIGN_SECTORS;
            let last_usable = total_sectors.saturating_sub(34);
            let min_sectors = (BOOT_BYTES + MIN_ROOT_BYTES) / SECTOR_BYTES;
            if last_usable.saturating_sub(first_usable) < min_sectors {
                return Ok(vec![]);
            }
            let size_bytes = (last_usable - first_usable + 1) * SECTOR_BYTES;
            return Ok(vec![FreeExtent {
                start_lba: first_usable,
                end_lba: last_usable,
                size_bytes,
            }]);
        }
    };

    let header = gd.primary_header().context("no primary header")?;
    let first_usable = header.first_usable;
    let last_usable = header.last_usable;

    let mut used: Vec<(u64, u64)> = gd
        .partitions()
        .values()
        .map(|p| (p.first_lba, p.last_lba))
        .collect();
    used.sort_by_key(|&(s, _)| s);

    let min_sectors: u64 = (BOOT_BYTES + MIN_ROOT_BYTES) / SECTOR_BYTES;

    let mut extents = Vec::new();
    let mut cursor = first_usable;

    for (part_start, part_end) in &used {
        if *part_start > cursor && part_start - cursor >= min_sectors {
            let start = cursor;
            let end = part_start - 1;
            let size_bytes = (end - start + 1) * SECTOR_BYTES;
            extents.push(FreeExtent {
                start_lba: start,
                end_lba: end,
                size_bytes,
            });
        }
        cursor = cursor.max(part_end + 1);
    }

    if last_usable >= cursor && last_usable - cursor + 1 >= min_sectors {
        let size_bytes = (last_usable - cursor + 1) * SECTOR_BYTES;
        extents.push(FreeExtent {
            start_lba: cursor,
            end_lba: last_usable,
            size_bytes,
        });
    }

    Ok(extents)
}

pub fn plan_empty_space(extent: &FreeExtent, overprovision_pct: u8) -> Result<PartitionPlan> {
    if overprovision_pct > 90 {
        anyhow::bail!("overprovisioning must be 90% or less");
    }

    let first = align_up(extent.start_lba);
    let last = align_down(extent.end_lba);
    if last <= first {
        anyhow::bail!("selected free space is too small after alignment");
    }

    let boot_sectors = BOOT_BYTES / SECTOR_BYTES;
    let boot_first = first;
    let boot_last = boot_first + boot_sectors - 1;
    let root_first = align_up(boot_last + 1);
    if root_first >= last {
        anyhow::bail!("selected free space is too small for boot and root partitions");
    }

    let root_total_sectors = last - root_first + 1;
    let op_sectors = root_total_sectors * overprovision_pct as u64 / 100;
    let root_last = last.saturating_sub(op_sectors);
    let root_bytes = sectors_to_bytes(root_first, root_last);
    if root_bytes < MIN_ROOT_BYTES {
        anyhow::bail!(
            "selected free space leaves only {} for root; need at least {}",
            format_bytes(root_bytes),
            format_bytes(MIN_ROOT_BYTES)
        );
    }

    Ok(PartitionPlan {
        extent: extent.clone(),
        boot: PlannedPartition {
            name: "boot".to_string(),
            part_type: PlannedPartitionType::Efi,
            first_lba: boot_first,
            last_lba: boot_last,
            size_bytes: sectors_to_bytes(boot_first, boot_last),
        },
        root: PlannedPartition {
            name: "cryptroot".to_string(),
            part_type: PlannedPartitionType::LinuxRoot,
            first_lba: root_first,
            last_lba: root_last,
            size_bytes: root_bytes,
        },
        overprovision_bytes: op_sectors * SECTOR_BYTES,
    })
}

pub fn is_ssd(disk: &Disk) -> bool {
    let path = format!("/sys/class/block/{}/queue/rotational", disk.name);
    fs::read_to_string(path)
        .map(|s| s.trim() == "0")
        .unwrap_or(false)
}

pub fn create_partitions_from_plan(
    disk: &Disk,
    plan: &PartitionPlan,
) -> Result<(PathBuf, PathBuf)> {
    // Determine how many partitions exist so we know the new partition numbers.
    // Also verify the plan doesn't overlap any existing partition.
    let existing_count = match GptConfig::new()
        .writable(false)
        .logical_block_size(LogicalBlockSize::Lb512)
        .open(&disk.path)
    {
        Ok(gd) => {
            let parts = gd.partitions();
            let overlaps = parts.values().any(|p| {
                ranges_overlap(
                    plan.boot.first_lba,
                    plan.root.last_lba,
                    p.first_lba,
                    p.last_lba,
                )
            });
            if overlaps {
                anyhow::bail!("partition plan overlaps an existing partition; aborting");
            }
            parts.len() as u32
        }
        Err(_) => 0, // blank disk — no GPT yet
    };

    let boot_num = existing_count + 1;
    let root_num = existing_count + 2;
    let disk_str = disk.path.to_str().unwrap();

    // On a blank disk create the GPT label first.
    if existing_count == 0 {
        Command::new("parted")
            .args(["--script", disk_str, "mklabel", "gpt"])
            .status()
            .context("parted mklabel gpt")?
            .success()
            .then_some(())
            .context("parted mklabel gpt failed")?;
    }

    // Add EFI boot partition.
    Command::new("parted")
        .args([
            "--script",
            disk_str,
            "mkpart",
            &plan.boot.name,
            &format!("{}s", plan.boot.first_lba),
            &format!("{}s", plan.boot.last_lba),
        ])
        .status()
        .context("parted mkpart boot")?
        .success()
        .then_some(())
        .context("parted mkpart boot failed")?;

    // Add root partition.
    Command::new("parted")
        .args([
            "--script",
            disk_str,
            "mkpart",
            &plan.root.name,
            &format!("{}s", plan.root.first_lba),
            &format!("{}s", plan.root.last_lba),
        ])
        .status()
        .context("parted mkpart root")?
        .success()
        .then_some(())
        .context("parted mkpart root failed")?;

    // Set ESP flag on the boot partition.
    Command::new("parted")
        .args([
            "--script",
            disk_str,
            "set",
            &boot_num.to_string(),
            "esp",
            "on",
        ])
        .status()
        .context("parted set esp")?
        .success()
        .then_some(())
        .context("parted set esp failed")?;

    // parted notifies the kernel itself; give udev a moment to create nodes.
    let _ = Command::new("udevadm")
        .args(["settle", "--timeout=15"])
        .status();

    // Poll until both device nodes exist (up to 15 s).
    let boot_part = disk.part_path(boot_num);
    let root_part = disk.part_path(root_num);
    let deadline = std::time::Instant::now() + Duration::from_secs(15);
    while std::time::Instant::now() < deadline {
        if boot_part.exists() && root_part.exists() {
            break;
        }
        thread::sleep(Duration::from_millis(300));
    }
    if !boot_part.exists() || !root_part.exists() {
        anyhow::bail!(
            "partition nodes {:?} / {:?} did not appear after 15 s",
            boot_part,
            root_part
        );
    }

    Ok((boot_part, root_part))
}

fn ranges_overlap(a_first: u64, a_last: u64, b_first: u64, b_last: u64) -> bool {
    a_first <= b_last && b_first <= a_last
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plan_splits_single_extent_into_boot_and_root() {
        let extent = FreeExtent {
            start_lba: 2048,
            end_lba: (64 * 1024 * 1024 * 1024 / SECTOR_BYTES) - 1,
            size_bytes: 64 * 1024 * 1024 * 1024,
        };

        let plan = plan_empty_space(&extent, 10).unwrap();

        assert_eq!(plan.boot.part_type, PlannedPartitionType::Efi);
        assert_eq!(plan.root.part_type, PlannedPartitionType::LinuxRoot);
        assert_eq!(plan.boot.size_bytes, BOOT_BYTES);
        assert!(plan.root.first_lba > plan.boot.last_lba);
        assert!(plan.root.size_bytes >= MIN_ROOT_BYTES);
        assert!(plan.overprovision_bytes > 0);
    }

    #[test]
    fn plan_rejects_small_extents() {
        let extent = FreeExtent {
            start_lba: 2048,
            end_lba: (4 * 1024 * 1024 * 1024 / SECTOR_BYTES) - 1,
            size_bytes: 4 * 1024 * 1024 * 1024,
        };

        assert!(plan_empty_space(&extent, 0).is_err());
    }
}
