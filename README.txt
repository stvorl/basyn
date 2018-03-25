INTRODUCTION:

An idea and some code of this project was borrowed from Bscp project (https://github.com/vog/bscp).
Thanks to Volker Diels-Grabsch for simple and effective solution. But i need for some more features and parallel computation on both sides. Copyright information is included in the beginning of the script.


DESCRIPTION:

Basyn is an abbreviation for "Block device Advanced SYNchronization tool".
It copies data from one block device (or file) to another (located in the network - via SSH, or locally).

First device ("local device") is always local. Second device ("remote device") can be located either at local machine or in the network.

There are two possible actions:
1. PUSH, when data is transferred from local device to remote.
2. POP, which puts data to local device from remote (which is not implemented at the moment, but I am planning to implement it soon)

And two possible modes:
1. COPY. Data is sequentially copied block-by-block. Is is usable for first-time synchronization to reduce read operations and CPU load on receiving side.
2. SYNC. The script uses hash function (SHA1 by default, others are available) to read both devices, and detect changed blocks without direct data exchange. Then, only changed blocks will be transferred.

Compression is used (by default) in both modes to reduce traffic.
Because of possible device role exchange, they will be also referenced below as "source device" and "receiving device".


INSTALLATION:

Following software have to be installed:
  Local machine: Python interpreter and SSH client
  Remote machine: Python interpreter and SSH server
Place this script to any folder at the local machine.
Local and remote users should be assigned with necessary permissions (r, rw) for corresponding devices.
Certificate authentication is strongly recommended to avoid interactive password prompt during script execution.


USAGE:

basyn <options>
Options (* for mandatory, = for value):
 * -l, --local=     - Local device, for example /dev/sda1.
 * -r, --remote=    - Remote device, for example /dev/vgroup1/copy-sda1.
   -h, --host=      - Remote hostname or IP address for SSH connection (for example 10.0.0.1 or bkp.corp.site).
                      If omitted, localhost is presumed, and direct process connection is used instead of SSH.
   -p  --port=      - Remote host SSH port (default is 22).
   -u  --user=      - Remote user for SSH connection. If omitted, current local user is presumed.
   -a  --action=    - One of the actions:
                      PUSH - use local device as source, remote - as destination;
                      POP  - use remote device as source, local - as destination.
                      If omitted, no data will be transferred. Only device existence will be performed.
 * -m  --mode=      - One of synchronization modes (mandatory if any --action selected):
                      SYNC - copy only changed blocks, detected by parallel hash computation and comparison;
                      COPY - copy whole data (usable for first time).
       --recheck    - Re-check data after sync (or immediately, if --action and --mode is not specified).
       --stat       - Display data transfer statistics after completion.
       --verbose    - Be verbose in stdout about what is script doing (usable for logging).
       --progress   - Display progress indicator to stderr.
       --debug      - Display debug info to stderr (may generate significant amount of information when syncing
                      BIG devices).
       --hash=      - Hash function name (SHA1 (used by default), SHA224, SHA256, SHA384, SHA512, BLAKE2B,
                      BLAKE2S, MD5 are supported).
       --buffer=    - Buffer size in kilobytes (2048, e.g. 2M, by default) for sequential comparison
       --chunk=     - Chunk size in kilobytes for detailed comparison.
                      Allows to trade lesser traffic (by transferring only real changed small chunks, instead
                      of whole --buffer) for CPU time (used for second data hashing bypass)
                      Same as buffer if omitted (e.g. no detailed comparison)
       --zlevel=    - ZLIB compression level (0 - no compression, saves CPU, 9 - best compression, saves
                      bandwidth. Is 9 by default)

Exit codes:
  0 - A-OK. Data matches on both devices.
  1 - Command line parsing error (displayed). It didn't change any data.
  2 - Copy / sync error (displayed). Data may be already changed on receiving device, but there are no guarantees, that
      it matches source device.


EXAMPLES:

To silently (no messges) copy local /dev/sda1 to remote /dev/sda1:
  basyn --local=/dev/sda1 --remote=/dev/sda1 --host 10.0.0.1 --action=PUSH --mode=SYNC

Same as above, but with short options:
  basyn -l /dev/sda1 -r /dev/sda1 -h 10.0.0.1 -a PUSH -m SYNC

In addition to above:
  Display some relaxing info about how it doing.
  ... --verbose

  No compression, to reduce CPU load, while bandwidth is not our bottleneck.
  ... --zlevel=0

  Longer buffer (8M). Better IO and analysis speed, less command traffic (and delays), but more data traffic, because whole buffer is transferred even if one byte changed. Usable for connections with high bandwidth, but slow ping, or for big expected changes.
  ... --buffer=8192

  Detailed comparison: every buffer (2M by default), which differs, will be split to 64KB chunks, every will be compared separately, and only necessary 64-kb chunks will be transferred. Will reduce data traffic, but raise command traffic. Usable for small expected changes, low bandwidth, but fast ping.
  ... --chunk=64

  Do full re-check, whether data matches on both devices, or not.
  ... --recheck

  Display statistics
  ... --stat
  with following description:
    Device size: Size of the source device in bytes
    Traffic:     Rx - received,
                 Tx - transferred,
                 Both - total
    Ratio:       Relation of total transferred bytes to source device size, in %. Reflects traffic economy compared to by-byte transfer without any compression

    Time:        Total process time in seconds.
    Bandwidth:   Real:      Relation of transferred bytes to time. Reflects real network connection usage.
                 Effective: Relation of device size to time.

No data transfer, re-check only:
  basyn --local=/dev/sda1 --remote=/dev/sda1 --host 10.0.0.1 --recheck

NOTES:

1. In any selected way, during synchronization, one-time sequental read of both devices will be performed (at least, one read on one write for COPY mode). For slow HDDs and big volume sizes this can take hours. It also can reduce lifetime of devices, when used on regular basis. If it matters, you have to use DRBD (Distributed Replicated Block Device) instead. It will track changed blocks in realtime, schedule to transfer it and monitor synchronization status. It is really nice solution, but, sometimes, an overkill.

2. During COPY/SYNC, esp. of big devices, source device can take some changes by other processes. If changed area already passed by script, those changes will not be transferred to receiving device, and its data can be inconsistent.
If filesystem on source device is mounted for write, EVEN if it was no data direct writes, some metadata yet can be overwritten, depending of used abstraction layer (atime attribute, for example, by almost any filesystem driver). Things can be worse if device is given to virtual machine, that we cannot stop.
Even usage of --recheck will not help us to confirm "no-error-state" in those cases, because it is just another full read of devices, it takes time, and while the reading is on, the device can receive more changes by other processes.

So, it is strongly recommended, to remount filesystems read-only, or use LVM snapshots during sync time.
For example:
  lvcreate --size 10G --snapshot --name sync-mytome /dev/vgroup/mytome
  basyn --local=/dev/vgroup/sync-mytome --remote=/dev/vcopies/mytome --host=10.0.0.1 --action=PUSH --mode=SYNC
  lvremove --force /dev/vgroup/mytome

Even this - is not a solution to every possible trouble. You have to notice what activity is done at source device, because snapshot can be ALREADY inconsistent without stopping of some process, flushing cache, etc. You have to plan "data freezing" well by yourself.

3. Because this script works with raw data and doesn't know about its logical organization, you have to apply TRIM manually after sync, if receiving device is SSD and data is filesystem (by fstrim, for example).

4. You can be able to obtain good balance between --buffer, --chunk, --zlevel, but you will not jump over maximum read speed of source device. So, "Effective traffic" in statistics should strive to read speed limit.