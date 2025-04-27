INTRODUCTION:

An idea and some code of this project were borrowed from Bscp project (https://github.com/vog/bscp).
Special thanks to Volker Diels-Grabsch for providing a simple and effective solution.
However, this tool was created to support additional features I needed.
Copyright information is included at the beginning of the script.

DESCRIPTION:

Basyn stands for "Block device Advanced SYNchronization tool".
It copies data from one block device (or file) to another - either over the network via SSH or locally.

The first device (referred to as the local device) is always on the local machine.
The second device (the remote device) can reside either on the same machine or on a remote host.

There are two possible actions:
    PUSH - Transfer data from the local device to the remote device.
    PULL - Transfer data from the remote device to the local device.

And two possible modes:
    COPY - Copies data sequentially, block by block. Recommended for initial syncs to reduce read operations and CPU usage on the receiving side.
    SYNC - Uses a hash function (SHA1 by default; others are available) to compare both devices in parallel. Only modified blocks are transferred.

Compression is enabled by default in both modes to reduce network traffic.
To avoid confusion in role-swapping scenarios, devices are also referred below to as the "source device" and "receiving device"

INSTALLATION:

Required software:
    Local machine: Python interpreter and SSH client
    Remote machine: Python interpreter and SSH server
Place the script on the local machine in any convenient directory.
Ensure that both local and remote users have the necessary read/write permissions for the relevant devices.
It is strongly recommended to use certificate-based SSH authentication to avoid interactive password prompts during execution.

USAGE:

basyn <options>
Options (* for mandatory, = for value):
 * -l, --local=     - Local device (e.g., /dev/sda1)
 * -r, --remote=    - Remote device (e.g., /dev/vg_disk_backups/copy-sda1)
   -h, --host=      - Remote SSH hostname or IP address (e.g., 10.0.0.1 or bkp.corp.site).
                      If omitted, localhost is assumed. No SSH will be used.
   -p  --port=      - Remote SSH port (default: 22).
   -u  --user=      - Remote SSH user (default: same as current local user).
   -a  --action=    - One of the actions:
                      PUSH - use local device as source, remote - as destination;
                      PULL  - use remote device as source, local - as destination.
                      If omitted, no data transfer is performed - only device existence is verified.
 * -m  --mode=      - One of the synchronization modes (mandatory if any --action selected):
                      SYNC - copy only changed blocks, detected by parallel hash computation and comparison;
                      COPY - copy whole data (recommended for the initial run).
       --recheck    - Re-check data after sync (or immediately, if no --action and --mode is specified).
       --stat       - Show transfer statistics upon completion.
       --verbose    - Be verbose in stdout about what is script doing (usable for logging).
       --progress   - Show progress indicator to stderr.
       --debug      - Display debug info to stderr (may be extensive for large devices).
       --hash=      - Hash function (SHA1 (by default), SHA224, SHA256, SHA384, SHA512, BLAKE2B,
                      BLAKE2S, MD5).
       --buffer=    - Buffer size in KB for sequential comparison (default: 2048 KB, i.e., 2 MB)
       --chunk=     - Chunk size in kilobytes for detailed comparison.
                      Allows trading lesser traffic (by transferring only actually changed small chunks, instead
                      of whole --buffer) for CPU time (used for secondary data hashing bypass)
                      Not used by default.
       --zlevel=    - ZLIB compression level (0 - no compression, saves CPU, 9 - best compression, saves
                      bandwidth. Default: 9)

Exit codes:
  0 - A-OK. Data is identical.
  1 - Command line parsing error (displayed). No data was changed.
  2 - Copy / sync error (displayed). Data may have partitially  changed on receiving device, no match guarantees.

EXAMPLES:

Perform a silent sync of local source device /dev/sda1 to remote destination device /dev/sda1:
  basyn --local=/dev/sda1 --remote=/dev/sda1 --host 10.0.0.1 --action=PUSH --mode=SYNC

Same as above, using short options:
  basyn -l /dev/sda1 -r /dev/sda1 -h 10.0.0.1 -a PUSH -m SYNC

In addition to the above:
  Display some relaxing info about how it's doing.
  ... --verbose

  Disable compression (reduce CPU usage).
  ... --zlevel=0

  Use a larger buffer (8M). Improves I/O and analysis speed, reduces command traffic (and delays), but increases data traffic, since the entire buffer is transferred even if only a single byte has changed. Suitable for connections with high bandwidth but high latency (slow ping), or when large changes are expected.
  ... --buffer=8192

  For detailed comparison: each differing buffer (2M by default) will be split into 64KB chunks; each chunk will be compared separately, and only the necessary 64KB chunks will be transferred. This reduces data traffic but increases command traffic. Suitable for scenarios with small expected changes, low bandwidth, and fast ping.
  ... --chunk=64

  Perform a full re-check after sync to verify whether the data matches on both devices.
  ... --recheck

  Display statistics  
  ... --stat  
  with the following description:  
    Device size: Size of the source device in bytes  
    Traffic:     Rx - received,  
                 Tx - transferred,  
                 Both - total  
    Ratio:       Ratio of total transferred bytes to the source device size, in %.  
                 Reflects traffic economy compared to a full byte-by-byte transfer without compression.  

    Time:        Total process time in seconds.  
    Bandwidth:   Real:      Ratio of transferred bytes to time. Reflects actual network throughput.  
                 Effective: Ratio of synced device size to time.

No data transfer, re-check only:
  basyn --local=/dev/sda1 --remote=/dev/sda1 --host 10.0.0.1 --recheck

NOTES:

1. In any selected mode, at least a one-time sequential read of both devices will be performed during SYNC (and one read and one write during COPY). For slow HDDs and large volume sizes, this process can take hours. It may also reduce the lifespan of the devices if used regularly. If this is a concern, consider using DRBD (Distributed Replicated Block Device) instead. It tracks and marks changed blocks in real time and transfers only necessary changes, monitoring sync state.

2. During COPY/SYNC, esp. of big devices, source device can take some changes by other processes. If changed area already passed by script, those changes will not be transferred to receiving device, and its data can be inconsistent.
If filesystem on source device is mounted for write, EVEN if it was no data direct writes, some metadata yet can be overwritten, depending of used abstraction layer (atime attribute, for example, by almost any filesystem driver). Things can be worse if device is given to virtual machine, that we cannot stop.
Even usage of --recheck will not help us to confirm "no-error-state" in those cases, because it is just another full read of devices, it takes time, and while the reading is on, the device can receive more changes by other processes.

2. During COPY/SYNC, especially for large devices, the source device may be modified by other processes. If changes occur in areas that have already been processed by the script, those changes will not be transferred to the receiving device, leading to potential data inconsistency.  
If the filesystem on the source device is mounted with write access, even without direct data writes, some metadata may still be altered - depending on the abstraction layer in use (e.g., the atime attribute, which is updated by almost all filesystem drivers). The situation becomes even worse if the device is used by a virtual machine that cannot be stopped.  

Even using `--recheck` won't guarantee a "no-error state" in such cases, since it performs yet another full read of both devices - which takes time - and the source may be modified once again during this process.

Therefore, it is strongly recommended to remount filesystems as read-only during sync, or to use LVM snapshots as the synchronization source.
For example:
  lvcreate --size 10G --snapshot --name mytome-2sync /dev/vgroup/mytome
  basyn --local=/dev/vgroup/mytome-2sync --remote=/dev/vcopies/mytome --host=10.0.0.1 --action=PUSH --mode=SYNC
  lvremove --force /dev/vgroup/mytome-2sync

But even using a snapshot is not a silver bullet. Depending on which programs are using the source device, it's possible that its state at the moment the snapshot is taken may be internally inconsistent at higher levels (for example, an application has started writing, but hasn't finished writing all the planned data to a file). You may need to flush caches or stop certain processes. You have to carefully plan "data freezing" on your own, taking into account how the device is being used, and this is beyond the scope of this documentation.

3. The script operates on raw data and is unaware of filesystems. If syncing to an SSD, you have to TRIM manually on the receiving device afterward (using fstrim, for example)

4. You can experiment with --buffer, --chunk, and --zlevel to balance CPU, traffic, and speed. However, your effective speed won't exceed the maximum read/write rates of the source and detination devices or the maximum transter rate of network.
In fact, it may be even lower due to some issues with the script's asynchronous operation on both the local and remote machines.
