/* Minimal termcap stub for cross-compilation environments
 * where no native termcap/ncurses library is available.
 * Provides just enough for vim's --with-tlib=termcap check.
 * For a real terminal, install ncurses for the target. */
#include <string.h>
#include <stdio.h>

int tgetent(char *bp, const char *name) {
  /* Return 1 (success) with a minimal terminal description.
   * Vim works with TERM=xterm and built-in termcaps. */
  if (bp) strcpy(bp, "xterm");
  return 1;
}

int tgetnum(char *id) {
  return -1; /* not specified */
}

int tgetflag(char *id) {
  return 0; /* not present */
}

char *tgetstr(char *id, char **area) {
  return NULL; /* not available */
}

char *tgoto(const char *cm, int col, int row) {
  static char buf[32];
  snprintf(buf, sizeof(buf), "\033[%d;%dH", row + 1, col + 1);
  return buf;
}

int tputs(const char *str, int affcnt, int (*outc)(int)) {
  while (*str) outc(*str++);
  return 0;
}
