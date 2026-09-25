---
title: "Expanding Windows C Drive: A Practical Guide"
date: 2020-05-25
categories: Operations
tags: [Disk Management]
lang: en
label: 107_windows_ssd_partition_by_diskgenius
---

My 1TB SSD has been running for over two years, and the C drive is down to 13GB free. Maven local repos, Gradle caches, Node.js node_modules folders, Docker images, Windows Update caches — none of these space hogs care that you only gave yourself one C partition.

Here's the disk layout: the 198GB C drive is sandwiched between the EFI partition and a recovery partition, while the 732GB D drive sits to the right of the recovery partition with plenty of free space. Windows Disk Management is useless for this layout — shrinking D produces unallocated space at the far right end of the disk, separated from C by the entire D drive and a recovery partition. There's no way to extend C from there.

This article documents the complete process of using DiskGenius to carve 200GB from the front of D, move it past the recovery partition, and merge it into C.

> **Risk warning:** Partition resizing involves changes to the underlying disk structure. DiskGenius's non-destructive resize function doesn't lose data under normal circumstances, but the official documentation explicitly warns: bad sectors, sudden power loss, or system crashes can all cause operation failure. Back up important data on both C and D before proceeding.

## Why Windows Disk Management Can't Handle This

Open Disk Management (Win+X → Disk Management), right-click D, and run "Shrink Volume." The result:

```
[C Drive 198GB] [Recovery Partition 918MB] [D Drive 532GB] [Unallocated 200GB]
```

C's "Extend Volume" button is still grayed out. The reason: Windows Disk Management's extension rule is inflexible — C can only extend into unallocated space immediately to its right, with no other partitions in between. In the layout above, C's right neighbor is the recovery partition, and the unallocated space is at the far end of the disk. Both block the extension path.

To successfully expand C, we need this final layout:

```
[C Drive 198GB] [Unallocated 200GB] [Recovery Partition 918MB] [D Drive 532GB]
```

The 200GB unallocated space must sit immediately to the right of C. That means we need to "move" the recovery partition — which is beyond what Windows' built-in tools can do.

## Pre-Operation Checklist

Before opening DiskGenius, a few things need confirming.

**Back up your data.** DiskGenius's partition resizing is non-destructive under normal conditions, but the process involves physically moving large blocks of data and can take 5 to 30 minutes. Any unexpected interruption during that window carries risk. Copy important files to an external drive or cloud storage — this step isn't optional.

**Check BitLocker status.** If there's a lock icon on C or the recovery partition, BitLocker encryption is enabled. Before resizing partitions, go to Control Panel → BitLocker Drive Encryption and either pause or turn off encryption. Otherwise, after moving partitions, the system may demand a 48-digit recovery key that you almost certainly haven't saved.

**Ensure stable power.** Laptops must be plugged in. The system can't sleep or shut down during the operation. DiskGenius will require a reboot into a pre-installation environment when moving system-related partitions. The whole process runs automatically, but a power cut mid-operation will cause problems.

**Download DiskGenius.** Get the latest version from the official website, making sure to choose the 64-bit edition matching your system. Run as administrator after installation.

## Step 1: Free 200GB from the Front of D

This is the foundation of the entire operation. Right-click D and select "Resize Partition."

The dialog shows three key values: the adjusted capacity, space before the partition, and space after the partition. The most common mistake here is putting the 200GB behind D. If you release space from the rear, the result is:

```
[C Drive] [Recovery Partition] [D Drive 532GB] [Unallocated 200GB]
```

Unallocated space at the far right end of the disk, miles away from C — completely useless for extending C.

The correct approach: release space from the front of D. Set the adjusted capacity to approximately 532GB (original 732GB minus 200GB). Enter 200 in "Space before partition" with the unit set to GB; set "Space after partition" to 0. After D shrinks, the 200GB unallocated space appears to the left of D and to the right of the recovery partition:

```
[C Drive 198GB] [Recovery Partition 918MB] [Unallocated 200GB] [D Drive 532GB]
```

Click OK, verify the layout is correct on the main screen, then click "Save Changes" in the top left to apply.

## Step 2: Move the Recovery Partition

Now the 200GB unallocated space is in position, but the recovery partition is still blocking it from reaching C. We need to move the recovery partition entirely to the right, letting the unallocated space "pass through" to C's right side.

Right-click the recovery partition (the 918MB MS Recovery), select "Resize Partition." In the dialog, set "Space before partition" to 200GB and keep "Space after partition" at 0. What this does: tells DiskGenius to reserve 200GB of space in front of the recovery partition, pushing the partition itself to the right.

A useful trick to verify the setting: check the "Starting sector number" at the top of the window. If that number has clearly increased (e.g., from 400 million to 800 million), the recovery partition has indeed been shifted right.

There's also a shortcut: DiskGenius's resize dialog usually has a "Merge to" option where you can directly select merging into C. Checking this completes both the recovery partition move and the C expansion in one step — no need for Step 3 separately. If this option isn't available or you prefer to proceed step by step for control, just move the recovery partition as described above and then do Step 3 manually.

After confirming the settings, click "Start" to execute. Since this involves operations near system partitions, DiskGenius will prompt for a restart. In the popup, check "Restart" and "Prevent system sleep during execution," then confirm.

## Step 3: Expand C

If you didn't use the "Merge to C" option in the previous step, after the restart and Windows login, the disk layout should be:

```
[C Drive 198GB] [Unallocated 200GB] [Recovery Partition 918MB] [D Drive 532GB]
```

The 200GB unallocated space is now immediately to the right of C — conditions for expansion are met. Right-click C, select "Resize Partition," drag C's right-side slider all the way to the right to consume the full 200GB unallocated space. Confirm and save changes. This time a restart usually isn't needed — C extends directly.

## Final Result

After completion, the disk layout becomes:

```
┌──────┬──────┬────────────────┬────────┬──────────────┐
│ EFI  │Free  │       C        │Recovery│      D       │
│100MB │100MB │    ≈398GB      │918MB   │    ≈532GB    │
└──────┴──────┴────────────────┴────────┴──────────────┘
```

C expanded from 198GB to approximately 398GB; D shrank from 732GB to approximately 532GB. Actual displayed capacity may vary slightly due to GB/GiB conversion — don't worry about exact numbers.

The entire process can be summarized in a flow diagram:

```
Initial state
[EFI][Free][ C 198GB ][Recovery 918MB][Free 101MB][ D 732GB ]

        ↓ Free 200GB from front of D

[EFI][Free][ C 198GB ][Recovery 918MB][ Free 200GB ][D 532GB]

        ↓ Move recovery partition right (or merge into C in one step)

[EFI][Free][ C 198GB ][ Free 200GB ][Recovery 918MB][D 532GB]

        ↓ C consumes 200GB unallocated space

[EFI][Free][     C ≈398GB      ][Recovery 918MB][D ≈532GB]
```

## Common Questions

**Will moving the recovery partition affect system recovery?** No. Windows Recovery Environment (WinRE) boot association uses the partition's GUID, not a fixed position. DiskGenius updates the relevant partition table records when moving partitions — the system will still correctly identify the recovery environment after reboot.

**What if power fails or a BSOD occurs during the operation?** If the operation just errors out during the execution phase, data usually isn't damaged — reboot and retry. If the system won't boot after a BSOD, use a PE boot disk, open DiskGenius, and check the partition table for errors (right-click disk → Check Partition Table Errors). Rebuild the boot record if necessary.

**What if my partition layout is different from this article?** Say the partition between C and unallocated space is an ESP partition or MSR reserved partition instead — the approach is identical: identify the partition blocking the way, use "Resize Partition" to move it entirely away from C, and let the unallocated space sit adjacent to C.

**Is it mandatory to free space from the front of D?** Absolutely. Space freed from the rear of D ends up at the far end of the disk, separated from C by the entire D drive and recovery partition — completely useless for C expansion. This is the most common operational mistake.

## After Expansion: Treating the Symptom or the Cause

Expanding C from 198GB to 398GB is plenty for the short term. But if your development environment is driving continuous space growth, the problem will resurface. Maven repos, Gradle caches, npm global packages, Docker images, WSL virtual disks — these things grow faster than you'd expect.

Before or after expanding, it's worth spending half an hour on cleanup. Move the Maven local repo to D and set up a symlink, change `GRADLE_USER_HOME` to D, move npm global install path to D, relocate Docker's virtual disk file to D. Configure these once and you won't need to worry about C drive space again.

Simply expanding the partition treats the symptom. Moving continuously growing development caches off the system drive treats the cause.
