#!/usr/bin/env python3
"""Drive a VM serial console through its host pseudo-TTY (UTM 'ptty' serial
port, or QEMU '-serial pty').

Usage: serial-exec.py <tty> [--login USER] [--wait-for TEXT] [--timeout SEC] [--force] [CMD ...]
       serial-exec.py <tty> --interactive [--name NAME] [--force]

Scripted: sends a newline, optionally logs in, runs each CMD, and prints
everything the guest wrote. Exits non-zero if --wait-for TEXT never appears.
Interactive: connects the terminal to the console; Ctrl-] quits.

A serial console has one input stream: with two readers attached, each byte
goes to only one of them and both see garbled output. So the console is
locked (flock) and refused while another process has it open; --force stops
that process and takes the console over.
Uses only the Python standard library.
"""
import argparse, errno, fcntl, os, re, select, signal, subprocess, sys, termios, time, tty

MARK = "__SERIAL_EXEC_DONE__"
QUIT = b"\x1d"  # Ctrl-]


def fail(msg):
    print(f"serial-exec: {msg}", file=sys.stderr)
    sys.exit(1)


def holders(path):
    """PIDs of other processes that have the console open, except the VM
    itself (lsof; /proc where lsof is missing)."""
    pids = set()
    try:
        out = subprocess.run(["lsof", "-t", path], capture_output=True, text=True).stdout
        pids = {int(p) for p in out.split()}
    except FileNotFoundError:
        real = os.path.realpath(path)
        for pid in os.listdir("/proc") if os.path.isdir("/proc") else []:
            try:
                if pid.isdigit() and any(os.readlink(f"/proc/{pid}/fd/{f}") == real
                                         for f in os.listdir(f"/proc/{pid}/fd")):
                    pids.add(int(pid))
            except OSError:
                pass
    pids.discard(os.getpid())
    return sorted(p for p in pids if "qemu" not in describe(p).lower())


def describe(pid):
    """'serial-exec.py /dev/ttys010 --interactive (terminal ttys015)'"""
    out = subprocess.run(["ps", "-o", "tty=,command=", "-p", str(pid)],
                         capture_output=True, text=True).stdout.strip()
    if not out:
        return "exited"
    term, _, cmd = out.partition(" ")
    words = cmd.split()
    # Drop the interpreter path: "python3 .../serial-exec.py ..." -> "serial-exec.py ..."
    for i, w in enumerate(words):
        if w.endswith("serial-exec.py"):
            words = [os.path.basename(w)] + words[i + 1:]
            break
    cmd = " ".join(words)
    if len(cmd) > 70:
        cmd = cmd[:67] + "..."
    where = f" (terminal {term})" if term not in ("??", "?") else ""
    return cmd + where


def gone(pids, timeout):
    end = time.time() + timeout
    while time.time() < end:
        pids = [p for p in pids if alive(p)]
        if not pids:
            return []
        time.sleep(0.1)
    return pids


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def open_console(path, force):
    """Open the console pty and take the exclusive lock, or exit with a
    message naming whoever else has it."""
    try:
        fd = os.open(path, os.O_RDWR | os.O_NOCTTY)
    except OSError as e:
        fail(f"cannot open {path}: {e.strerror} (is the VM running?)")
    # Raw mode right away: in the default mode the pty echoes whatever the
    # guest prints back to the guest, and that queue can fill up and block.
    # TCSANOW: do not wait for queued output to drain (it may never).
    tty.setraw(fd, termios.TCSANOW)
    for attempt in (1, 2):
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            locked = True
        except OSError as e:
            if e.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                raise
            locked = False
        # Readers that do not lock (older serial-exec.py, screen, cu) count too
        others = holders(path)
        if locked and not others:
            return fd
        if not force or attempt == 2:
            break
        for p in others:
            print(f"serial-exec: stopping PID {p}: {describe(p)}", file=sys.stderr)
            try:
                os.kill(p, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for p in gone(others, 3):
            os.kill(p, signal.SIGKILL)
        gone(others, 2)
        if not locked:
            time.sleep(0.2)
    lines = [f"PID {p}: {describe(p)}" for p in others] or ["another process (not found by lsof)"]
    if force:
        fail(f"console {path} is still in use by\n  " + "\n  ".join(lines))
    fail(f"console {path} is already in use by\n  " + "\n  ".join(lines) +
         "\nQuit that console (Ctrl-]) or close its terminal, or rerun with --force"
         " to take it over.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tty")
    ap.add_argument("--login", help="user name to send at a 'login:' prompt")
    ap.add_argument("--wait-for", help="text that must appear in the output")
    ap.add_argument("--timeout", type=float, default=60)
    ap.add_argument("--interactive", action="store_true", help="attach the terminal; Ctrl-] quits")
    ap.add_argument("--name", default="VM", help="VM name for messages")
    ap.add_argument("--force", action="store_true",
                    help="stop any other process using the console and take it over")
    ap.add_argument("cmds", nargs="*")
    a = ap.parse_intermixed_args()

    # SIGTERM / SIGHUP (closed terminal): unwind, so the terminal is restored
    for s in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, lambda sig, _: sys.exit(128 + sig))

    fd = open_console(a.tty, a.force)  # raw: no line buffering / echo on the host side
    if a.interactive:
        interactive(fd, a.name)
        return
    termios.tcflush(fd, termios.TCIOFLUSH)
    buf = ""
    pending = ""

    def read_until(pattern, timeout):
        nonlocal buf, pending
        end = time.time() + timeout
        while time.time() < end:
            if pattern and pattern in buf:
                return True
            r, _, _ = select.select([fd], [], [], 0.2)
            if r:
                try:
                    data = os.read(fd, 4096)
                except OSError:  # Linux: EIO once QEMU closed the pty
                    data = b""
                if not data:
                    fail(f"console closed: {a.name} stopped")
                raw = pending + data.decode(errors="replace").replace("\r", "")
                # Keep a possibly split escape sequence for the next read
                cut = raw.rfind("\x1b")
                pending = raw[cut:] if cut != -1 and len(raw) - cut < 4 else ""
                chunk = raw[: len(raw) - len(pending)]
                while "\x1b[6n" in chunk:
                    # Answer the cursor-position query BusyBox line editing
                    # sends, or the shell stalls waiting for a terminal reply
                    os.write(fd, b"\x1b[1;1R")
                    chunk = chunk.replace("\x1b[6n", "", 1)
                sys.stdout.write(chunk)
                sys.stdout.flush()
                buf += chunk
        return pattern is not None and pattern in buf

    def send(line):
        os.write(fd, (line + "\r").encode())

    LOGIN = re.compile(r"login: ?$")
    # "host:~# " / "user@host$ ": the prompt char follows a non-space, non-'#'
    # character, so progress bars ("####  ") never match; "~ # " (BusyBox) is
    # a single word, a space and the prompt char on its own line
    SHELL = re.compile(r"([^\s#][#$]|^\S+ [#$]) $")

    def at_prompt(pattern):
        # Only the text after the last newline counts
        return bool(pattern.search(buf.rsplit("\n", 1)[-1]))

    end = time.time() + a.timeout
    os.write(fd, b"\x03")  # Ctrl-C: drop any half-typed line
    send("")
    if a.login:
        # Wait (through boot) for a login prompt or an already open shell;
        # poke with Enter only when the console has been quiet for a while
        logged_in = False
        while time.time() < end and not logged_in:
            size = len(buf)
            read_until(None, 3)
            if at_prompt(LOGIN):
                buf = ""
                send(a.login)
            elif at_prompt(SHELL):
                logged_in = True
            elif len(buf) == size:
                send("")
        if not logged_in:
            print("\nserial-exec: no shell prompt before timeout", file=sys.stderr)
            sys.exit(1)
    if a.cmds:
        split = MARK[:4] + "''" + MARK[4:]  # echoed line must not match MARK
        send("; ".join(a.cmds) + f"; echo {split}")
        read_until(MARK + "\n", max(1, end - time.time()))
    ok = True
    if a.wait_for:
        ok = read_until(a.wait_for, max(1, end - time.time()))
    os.close(fd)
    sys.exit(0 if ok else 1)


def write_all(fd, data):
    while data:
        data = data[os.write(fd, data):]


def interactive(fd, name):
    """Bridge stdin/stdout and the console until Ctrl-] or the VM goes away.

    Nothing is sent on attach: a newline would run whatever is left on the
    guest's command line (and disturb a full-screen program)."""
    stdin, stdout = sys.stdin.fileno(), sys.stdout.fileno()
    saved = termios.tcgetattr(stdin) if os.isatty(stdin) else None
    print(f"connected to the {name} console; Ctrl-] quits, Enter shows the prompt", file=sys.stderr)
    try:
        cols, rows = os.get_terminal_size(stdout)
        if (cols, rows) != (80, 24):
            # The guest cannot learn the size over a serial line; it assumes 80x24
            print(f"(this terminal is {cols}x{rows}; for vim/less run in the guest: "
                  f"stty rows {rows} cols {cols})", file=sys.stderr)
    except OSError:
        pass
    why = "disconnected (the VM keeps running)"
    if saved:
        tty.setraw(stdin)
    try:
        while True:
            r, _, _ = select.select([fd, stdin], [], [])
            if fd in r:
                try:
                    data = os.read(fd, 4096)
                except OSError:  # Linux: EIO once QEMU closed the pty
                    data = b""
                if not data:
                    why = f"console closed: {name} stopped"
                    break
                write_all(stdout, data)
            if stdin in r:
                data = os.read(stdin, 1024)
                if not data:  # EOF on piped input
                    break
                if QUIT in data:
                    write_all(fd, data[: data.index(QUIT)])
                    break
                try:
                    write_all(fd, data)
                except OSError:
                    why = f"console closed: {name} stopped"
                    break
    except KeyboardInterrupt:  # Ctrl-C when stdin is not a terminal
        pass
    finally:
        if saved:
            termios.tcsetattr(stdin, termios.TCSADRAIN, saved)
        print(f"\r\n{why}", file=sys.stderr)


if __name__ == "__main__":
    main()
