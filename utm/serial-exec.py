#!/usr/bin/env python3
"""Drive a VM serial console through its host pseudo-TTY (UTM 'ptty' serial port).

Usage: serial-exec.py <tty> [--login USER] [--wait-for TEXT] [--timeout SEC] [CMD ...]

Sends a newline, optionally logs in, runs each CMD, and prints everything the
guest wrote. Exits non-zero if --wait-for TEXT never appears. Uses only the
Python standard library that ships with macOS (Xcode Command Line Tools).
"""
import argparse, os, re, select, sys, termios, time, tty

MARK = "__SERIAL_EXEC_DONE__"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tty")
    ap.add_argument("--login", help="user name to send at a 'login:' prompt")
    ap.add_argument("--wait-for", help="text that must appear in the output")
    ap.add_argument("--timeout", type=float, default=60)
    ap.add_argument("cmds", nargs="*")
    a = ap.parse_intermixed_args()

    fd = os.open(a.tty, os.O_RDWR | os.O_NOCTTY)
    tty.setraw(fd)  # no line buffering / echo on the host side
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
                raw = pending + os.read(fd, 4096).decode(errors="replace").replace("\r", "")
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
    # character, so progress bars ("####  ") never match
    SHELL = re.compile(r"[^\s#][#$] $")

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


if __name__ == "__main__":
    main()
