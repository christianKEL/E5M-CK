# Ender 5 Max — Factory Reset Tutorial (for total beginners)

This guide walks you through installing a factory-reset script on your **stock Ender 5 Max** and then running it. No previous Linux experience needed — just copy and paste.

You'll do this **once**. After install, you'll be able to factory-reset the printer either with an SSH command or by plugging in a USB stick.

**Time needed:** about 10 minutes.

---

## ⚠️ Before you start — read this

This tutorial **only works if both of the following are true**:

1. **You have working access to the Nebula touchscreen** (it powers on, responds to taps, and you can navigate menus), **OR** root access has already been enabled on the printer at some earlier point.
2. **The printer is connected to the same WiFi network as your PC** (or via Ethernet to the same router).

**Why this matters:** Root SSH access on the Ender 5 Max can only be enabled from the screen (Settings → Root Account Information), and the SSH password is **only displayed on the screen** after you accept the EULA. There is no factory/default SSH password you can use without going through the screen at least once.

If your screen is broken, frozen, or otherwise unusable **and** root has never been enabled on the printer, **stop here** — the steps below won't work. You'd need to repair the screen, reflash firmware via USB, or use a pre-rooted firmware image first. Those topics are outside this tutorial.

---

## What you need

- A Windows PC (PowerShell is already built in)
- Your printer powered on and connected to the same WiFi as your PC
- A few minutes of patience

> 💡 *"SSH" just means "remote terminal". You'll type commands on your PC and they'll execute on the printer.*

---

## PART 1 — Prepare the printer

### Step 1: Enable root access on the printer

On the printer's touchscreen:

1. Tap the **gear icon** (Settings)
2. Tap **Root Account Information**
3. A long warning text appears. Scroll to the **bottom** of the text.
4. Check the box that says "I have read and accept..."
5. Tap **Next Step**
6. Wait about 30 seconds.
7. **Important** — the screen will now show you the **username** (`root`) and the **password** for SSH. Write them down or take a picture. Per Creality's official guide, "Enter 'Settings - Root Account Information', and accept the 'Warning', then you can get the root account and password of your printer." Creality has used different passwords across firmware versions (`creality_2023`, `creality_2024`, `Creality@2024_Wh_464`, and others) — the one your printer is showing right now is the *only* one you can trust.
8. Confirm the status shows **Root** (usually in yellow).

✅ Root access is now enabled. This is permanent — you only do it once.

### Step 2: Note your printer's IP address

**The easy way — from the screen:**

1. Tap **Settings**
2. Tap the **Network** tab
3. Write down the IP address shown (e.g. `192.168.1.42`)

**If the screen is not accessible** (but root SSH was previously enabled — see the warning at the top), use one of these two alternatives:

#### Alternative A — Look in your internet box / router

1. Open a web browser on your PC
2. Go to your router's admin page. Common addresses: `http://192.168.1.1`, `http://192.168.0.1`, `http://mafreebox.freebox.fr` (Freebox), `http://livebox` (Orange Livebox), `http://192.168.1.254` (SFR/Bouygues).
3. Log in (admin password is usually on a sticker on the box)
4. Find the **Connected devices** / **DHCP** / **Network map** section
5. Look for a device named something like **Creality**, **Nebula**, **F004**, or a device you don't recognize. Note its IP.

#### Alternative B — Scan the network from PowerShell

Open PowerShell (Win key → type `powershell` → Enter), then:

1. Find your subnet by running:
   ```
   ipconfig
   ```
   Look at the line **IPv4 Address** under your active connection (Wi-Fi or Ethernet). Example: `192.168.1.27`. The "subnet prefix" is the first three numbers — here, `192.168.1`.

2. Sweep the network and list everything found. Replace `192.168.1` below with **your** prefix:
   ```
   1..254 | ForEach-Object { Start-Job { param($i) Test-Connection -Count 1 -Quiet "192.168.1.$i" } -ArgumentList $_ } | Wait-Job | Remove-Job; arp -a
   ```
   This takes ~30 seconds. It pings every address on your network in parallel, then prints the ARP table.

3. In the output, look for unfamiliar IP addresses (your printer is the one you don't recognize). To verify which one is the printer, you can connect to it via SSH (next step) — if the password from the screen works, you found it.

> 💡 *If neither alternative works, you really do need screen access. There's no other reliable way.*

Keep your IP address handy — you'll need it in the next step.

---

## PART 2 — Connect to the printer with PowerShell

### Step 3: Open PowerShell on Windows

1. Press the **Windows key** on your keyboard
2. Type **powershell**
3. Press **Enter**

A dark window with light text opens. That's PowerShell.

### Step 4: Connect via SSH

In the PowerShell window, type the following (replace `192.168.1.42` with **your** printer's IP from Step 2):

```
ssh root@192.168.1.42
```

Press Enter.

**What happens the first time:**

1. **You may see a warning:**
   > The authenticity of host '192.168.1.42' can't be established... Are you sure you want to continue connecting (yes/no)?

   Type **yes** and press Enter. This only appears the first time.

2. **You'll be asked for a password:**
   > root@192.168.1.42's password:

   Type the password that was displayed on the printer screen in **Step 1**. ⚠️ **Nothing will appear on screen as you type — no dots, no asterisks. This is normal, not broken.** Press Enter when done.

   > 💡 *If you didn't write it down, go back to the printer screen: Settings → Root Account Information. The password is shown there.*

3. **Success looks like this** — the prompt changes to something like:
   ```
   [root@F004 ~]#
   ```
   That `#` at the end means you're in. 🎉

---

## PART 3 — Install the factory-reset script

You're now talking to the printer. Three commands to copy and paste, one at a time.

### Step 5: Move to the temporary folder

```
cd /tmp
```

Press Enter. Nothing visible happens — that's fine.

### Step 6: Download the two files from GitHub

Copy and paste **the whole block** below into PowerShell, then press Enter:

```
wget --no-check-certificate -O install_factory_reset.sh https://raw.githubusercontent.com/christianKEL/E5M-CK/main-v2/installs/install_factory_reset.sh
wget --no-check-certificate -O S58factoryreset https://raw.githubusercontent.com/christianKEL/E5M-CK/main-v2/system/etc/init.d/S58factoryreset
```

You should see two short downloads, each ending with something like:
```
'S58factoryreset' saved
```

### Step 7: Run the installer

```
sh install_factory_reset.sh < S58factoryreset
```

Press Enter. You should see several lines that look like:

```
[14:32:01] Reading new S58factoryreset from stdin...
[14:32:01] Received: 1234 bytes, md5=abc...
[14:32:01] Backed up original /etc/init.d/S58factoryreset -> /usr/data/backup/S58factoryreset.orig
[14:32:01] Installed: /etc/init.d/S58factoryreset (md5=abc...)
[14:32:01] Smoke test: usage output OK.
[14:32:01] Done.
```

✅ The factory-reset script is now installed on your printer.

> 💡 *If something goes wrong here, the script prints `ERROR: ...` and stops. Nothing is broken — read the message, fix the issue, and re-run.*

---

## PART 4 — Run a factory reset

You now have **two ways** to factory-reset the printer at any time.

### Method A — Right now, from SSH

Still in the SSH session, type:

```
/etc/init.d/S58factoryreset reset
```

Press Enter. The printer will erase its user data and reboot. Wait until you see the stock welcome screen.

> ⚠️ This wipes your WiFi config, any installed mods, custom Klipper configs, and gcode files. Make sure you really want to do this.

### Method B — Later, with a USB stick

This works even if SSH is broken or the printer is offline.

1. Take a USB stick and **format it as FAT32**
2. Create an **empty file named `factory_reset`** at the root (no file extension)
   - On Windows: right-click in the USB drive window → New → Text Document → name it `factory_reset` and delete the `.txt` extension
   - If Windows hides extensions: Explorer → View → check "File name extensions"
3. **Power off** the printer
4. **Plug the USB stick** into the front USB port
5. **Power on** the printer
6. The factory reset runs automatically during boot

The printer keeps your WiFi settings; everything else is wiped.

---

## When you're done

To exit SSH and close PowerShell:

```
exit
```

Press Enter. The connection closes. You can close the PowerShell window.

---

## Troubleshooting

**"`ssh` is not recognized as a command"**
Your Windows version is too old or OpenSSH isn't installed. Open Settings → Apps → Optional Features → "Add a feature" → search for **OpenSSH Client** → install. Then re-open PowerShell.

**"Connection refused" or it just hangs**
- Are your PC and printer on the same WiFi network?
- Is the IP from Step 2 still correct? (Your router may have changed it — check the screen again.)
- Did you complete Step 1 (Enable Root Access) on the printer?

**"Permission denied" after typing the password**
- Caps Lock off?
- Did you type the password exactly? (The `@`, `_` and digits matter.)
- Try the other password (`creality_2023` if you tried `Creality@2024_Wh_464`, or vice versa).

**"Host key verification failed" / "Remote host identification has changed"**
This happens if you reinstalled firmware. Run this on your PC (replace IP):
```
ssh-keygen -R 192.168.1.42
```
Then connect again.

**`wget` says SSL/certificate error**
Use `curl` instead:
```
curl -kL -o install_factory_reset.sh https://raw.githubusercontent.com/christianKEL/E5M-CK/main-v2/installs/install_factory_reset.sh
curl -kL -o S58factoryreset https://raw.githubusercontent.com/christianKEL/E5M-CK/main-v2/system/etc/init.d/S58factoryreset
```

**`sh install_factory_reset.sh` says "md5 mismatch" or "size mismatch"**
The script was downloaded incompletely. Re-run the `wget` commands from Step 6, then try again.

---

*Tutorial built for the E5M-CK install_factory_reset.sh deployer — christianKEL/E5M-CK on GitHub.*
