#define _GNU_SOURCE

#include <sys/wait.h>

#include <err.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define _STR(x)      #x
#define STR(x)       _STR(x)

#define MAX_COMMAND  200
#define MAX_SCRIPT   80

typedef unsigned int u_int;

struct command {
  unsigned count;
  char script[MAX_SCRIPT + 1];
};

static int
cmp_commands(const void *_a, const void *_b)
{
  const struct command *a = _a, *b = _b;

  int ret = b->count - a->count; // XXX: Is this correct?
  if (ret == 0)
    ret = strcmp(a->script, b->script);

  return ret;
}

enum fgetline_status {
  FLN_OK = 0,
  FLN_EOF,
  FLN_TRUNC,
  FLN_ERR
};

static enum fgetline_status
fgetline(char *s, size_t capacity, FILE *f)
{
  char *ret = fgets(s, capacity, f);
  u_int length;

  if (!ret) {
    if (feof(f))
      return FLN_EOF;
    else
      return FLN_ERR;
  }

  length = strlen(s);

  if (s[length - 1] == '\n')
    s[length - 1] = '\0';
  else
    return FLN_TRUNC;

  return FLN_OK;
}

void
read_history(const char *filename, struct command *cmd,
             u_int *count, u_int capacity)
{
  FILE *f = fopen(filename, "r");
  enum fgetline_status status;
  u_int i;
  char buf[MAX_SCRIPT * 2], *rest;

  if (f == NULL) {
    *count = 0;
    return;
  }

  for (i = 0; i < capacity; i++) {
    status = fgetline(buf, sizeof(buf), f);

    if (status == FLN_EOF)
      break;
    if (status == FLN_ERR)
      err(1, "failed to read history line %u in %s", i + 1, filename);
    if (status == FLN_TRUNC)
      errx(1, "line %u in %s is too long", i + 1, filename);

    cmd[i].count = strtol(buf, &rest, 10);

    if (buf == rest)
      errx(1, "missing count on line %u of %s", i + 1, filename);
    if (rest[0] != ' ')
      errx(1, "missing separator space on line %u of %s", i + 1, filename);

    if ((size_t)snprintf(cmd[i].script, sizeof(cmd[i].script), "%s", rest + 1)
        >= sizeof(cmd[i].script))
      errx(1, "line %u in %s is too long", i + 1, filename);
  }

  (void)fclose(f);

  qsort(cmd, i, sizeof(*cmd), cmp_commands);
  *count = i;
}

void
write_history(const char *filename, struct command *cmd,
              u_int count, const char *new_script)
{
  int found = 0;
  char *tempfilename;
  FILE *f;
  int fd;
  u_int i;

  if (asprintf(&tempfilename, "%s_XXXXXX", filename) < 0)
    err(1, NULL);
  if ((fd = mkstemp(tempfilename)) < 0)
    err(1, "can't create temporary history file for %s", filename);
  if ((f = fdopen(fd, "w")) == NULL)
    err(1, "can't open %s", tempfilename);

  for (i = 0; i < count; i++) {
    if (!found && !strcmp(cmd[i].script, new_script)) {
      cmd[i].count++;
      found = 1;
    }

    if (fprintf(f, "%u %s\n", cmd[i].count, cmd[i].script) < 0)
      err(1, "failed to write line %u to %s", i + 1, tempfilename);
  }

  if (!found) {
    if (fprintf(f, "%u %s\n", 1, new_script) < 0)
      err(1, "failed to write line %u to %s", i + 1, tempfilename);
  }

  (void)fclose(f);
  (void)close(fd);

  if (rename(tempfilename, filename) < 0)
    err(1, "can't overwrite %s with %s", filename, tempfilename);

  free(tempfilename);
}

static void
spawn(char **argv, int *in_fd, int *out_fd)
{
  int in_fds[2], out_fds[2];

  if (pipe(in_fds) < 0 || pipe(out_fds) < 0)
    err(1, "pipe");

  switch (fork()) {
  case -1:
    err(1, "fork");
    /* NOTREACHED */
  case 0:
    if (dup2(in_fds[0], STDIN_FILENO) < 0 ||
        dup2(out_fds[1], STDOUT_FILENO) < 0)
      err(1, NULL);
    (void)close(in_fds[0]);
    (void)close(in_fds[1]);
    (void)close(out_fds[0]);
    (void)close(out_fds[1]);
    if (execvp(argv[0], argv) < 0)
      err(1, "failed to execute %s", argv[0]);
    /* NOTREACHED */
  default:
    (void)close(in_fds[0]);
    (void)close(out_fds[1]);
    *in_fd = in_fds[1];
    *out_fd = out_fds[0];
  }
}

char *
read_command(int argc, const char **argv, struct command *cmd, u_int count)
{
  FILE *in, *out;
  enum fgetline_status status;
  int in_fd, out_fd;
  u_int i;
  char **args;
  char *buf;

  /* Command, `argc` arguments, and the NULL terminator. */
  if (!(args = malloc((argc + 2) * sizeof(*args))))
    err(1, NULL);
  if (!(buf = malloc(MAX_SCRIPT + 1)))
    err(1, NULL);

  args[0] = "dmenu";
  memcpy(args + 1, argv, sizeof(*argv) * (argc + 1));
  spawn(args, &in_fd, &out_fd);

  if (!(in = fdopen(in_fd, "w")) ||
      !(out = fdopen(out_fd, "r")))
    err(1, NULL);

  for (i = 0; i < count; i++)
    if (fprintf(in, "%s\n", cmd[i].script) < 0)
      err(1, "error writing options to dmenu");

  if (fclose(in) == EOF)   /* Don't let us deadlock. */
    err(1, "error flushing output to dmenu");

  status = fgetline(buf, MAX_SCRIPT + 1, out);

  if (status == FLN_EOF)   /* Nothing to do */
    exit(0);
  if (status == FLN_ERR)
    err(1, "failed to read command");
  if (status == FLN_TRUNC)
    errx(1, "command must be <= %u bytes", MAX_SCRIPT);

  if (fclose(out) == EOF)
    err(1, "failed to flush output from dmenu");

  free(args);
  (void)wait(NULL);        /* Clean up the zombie. */

  return buf;
}

void
run_command(const char *command)
{
  char *argv[4];

  switch (fork()) {
  case -1:
    err(1, "fork");
    /* NOTREACHED */
  case 0:
    argv[0] = "/bin/sh";
    argv[1] = "-c";
    /* argv[2] = "exec $command" */
    argv[3] = NULL;

    if (asprintf(&argv[2], "exec %s", command) < 0)
      err(1, NULL);
    if (execvp(argv[0], argv) < 0)
      err(1, "failed to execute %s %s '%s'", argv[0], argv[1], argv[2]);
    /* NOTREACHED */
  }
}

char *
get_history_filename(void)
{
  char *filename;
  char *homedir;
  const char *format;

  if (!(homedir = getenv("HOME")))
    err(1, "$HOME is not defined");

  format = homedir[strlen(homedir)] == '/' ? "%s%s" : "%s/%s";
  if (asprintf(&filename, format, homedir, ".umenu_history2") < 0)
    err(1, NULL);

  return filename;
}

int
main(int argc, const char **argv)
{
  struct command cmd[200];
  u_int count;
  char *filename;
  char *new_script;

  filename = get_history_filename();
  read_history(filename, cmd, &count, sizeof(cmd) / sizeof(cmd[0]));
  new_script = read_command(argc - 1, argv + 1, cmd, count);
  write_history(filename, cmd, count, new_script);
  run_command(new_script);

  free(filename);
  free(new_script);

  return EXIT_SUCCESS;
}
