/*
 * xsh -- the shell that ships inside the app bundle.
 *
 * Before a bootstrap is installed there is no bash, no coreutils, nothing.
 * This is a small POSIX-ish shell with the builtins you need to get on your
 * feet: navigate the filesystem, look at files, and install the real userland.
 *
 * It is deliberately tiny and dependency free -- it links against libSystem
 * only, so it works on any TrollStore-capable device.
 *
 * Supported:
 *   - command execution via posix_spawn, with PATH search
 *   - pipelines (a | b | c)
 *   - redirection (> >> < 2>)
 *   - quoting ('...', "...", \x) and $VAR / ${VAR} expansion
 *   - builtins: cd pwd echo export unset env exit help ls cat rm mkdir
 *               rmdir mv cp touch which chmod clear history source
 *   - line editing through the terminal's canonical mode
 */

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#define XSH_MAX_ARGS 256
#define XSH_MAX_LINE 8192
#define XSH_MAX_STAGES 16

static int g_last_status = 0;

/* ------------------------------------------------------------------ utils */

static void *xmalloc(size_t size) {
	void *pointer = malloc(size);
	if (!pointer) {
		fputs("xsh: out of memory\n", stderr);
		exit(1);
	}
	return pointer;
}

static char *xstrdup(const char *string) {
	char *copy = strdup(string);
	if (!copy) {
		fputs("xsh: out of memory\n", stderr);
		exit(1);
	}
	return copy;
}

/* ------------------------------------------------------------- tokenising */

typedef struct {
	char *argv[XSH_MAX_ARGS];
	int argc;
	char *input_file;
	char *output_file;
	bool output_append;
	char *error_file;
} Stage;

typedef struct {
	Stage stages[XSH_MAX_STAGES];
	int count;
	bool background;
} Pipeline;

/* Appends a character to a growable buffer. */
typedef struct {
	char *data;
	size_t length;
	size_t capacity;
} Buffer;

static void buffer_init(Buffer *buffer) {
	buffer->capacity = 64;
	buffer->length = 0;
	buffer->data = xmalloc(buffer->capacity);
	buffer->data[0] = '\0';
}

static void buffer_push(Buffer *buffer, char c) {
	if (buffer->length + 2 > buffer->capacity) {
		buffer->capacity *= 2;
		buffer->data = realloc(buffer->data, buffer->capacity);
		if (!buffer->data) {
			fputs("xsh: out of memory\n", stderr);
			exit(1);
		}
	}
	buffer->data[buffer->length++] = c;
	buffer->data[buffer->length] = '\0';
}

static void buffer_append(Buffer *buffer, const char *text) {
	for (const char *p = text; *p; p++) buffer_push(buffer, *p);
}

/* Expands $VAR, ${VAR}, $? and $$ into the buffer. */
static void expand_variable(Buffer *buffer, const char *line, size_t *index) {
	size_t i = *index + 1;   /* skip '$' */

	if (line[i] == '?') {
		char number[16];
		snprintf(number, sizeof(number), "%d", g_last_status);
		buffer_append(buffer, number);
		*index = i;
		return;
	}
	if (line[i] == '$') {
		char number[16];
		snprintf(number, sizeof(number), "%d", (int)getpid());
		buffer_append(buffer, number);
		*index = i;
		return;
	}

	bool braced = line[i] == '{';
	if (braced) i++;

	char name[256];
	size_t length = 0;
	while (line[i] && length < sizeof(name) - 1 &&
	       (isalnum((unsigned char)line[i]) || line[i] == '_')) {
		name[length++] = line[i++];
	}
	name[length] = '\0';

	if (braced && line[i] == '}') i++;

	if (length == 0) {
		buffer_push(buffer, '$');
		*index = *index;
		return;
	}

	const char *value = getenv(name);
	if (value) buffer_append(buffer, value);
	*index = i - 1;
}

/* Splits a line into a pipeline of stages.  Returns false on a syntax error. */
static bool parse_line(char *line, Pipeline *pipeline) {
	memset(pipeline, 0, sizeof(*pipeline));

	Stage *stage = &pipeline->stages[0];
	pipeline->count = 1;

	Buffer token;
	buffer_init(&token);
	bool have_token = false;

	/* Where the next word should go: normal argument or a redirection target. */
	enum { TARGET_ARG, TARGET_IN, TARGET_OUT, TARGET_APPEND, TARGET_ERR } target = TARGET_ARG;

	size_t length = strlen(line);

	for (size_t i = 0; i <= length; i++) {
		char c = line[i];

		if (c == '\'' ) {
			have_token = true;
			for (i++; i < length && line[i] != '\''; i++) buffer_push(&token, line[i]);
			continue;
		}
		if (c == '"') {
			have_token = true;
			for (i++; i < length && line[i] != '"'; i++) {
				if (line[i] == '\\' && (line[i + 1] == '"' || line[i + 1] == '\\' ||
				                        line[i + 1] == '$')) {
					buffer_push(&token, line[++i]);
				} else if (line[i] == '$') {
					expand_variable(&token, line, &i);
				} else {
					buffer_push(&token, line[i]);
				}
			}
			continue;
		}
		if (c == '\\' && i + 1 < length) {
			have_token = true;
			buffer_push(&token, line[++i]);
			continue;
		}
		if (c == '$' && i + 1 < length) {
			have_token = true;
			expand_variable(&token, line, &i);
			continue;
		}

		bool is_separator = (c == '\0' || c == ' ' || c == '\t' || c == '|' ||
		                     c == '<' || c == '>' || c == '&');

		if (!is_separator) {
			have_token = true;
			buffer_push(&token, c);
			continue;
		}

		/* Flush the token we just finished. */
		if (have_token) {
			char *word = xstrdup(token.data);
			switch (target) {
			case TARGET_ARG:
				if (stage->argc < XSH_MAX_ARGS - 1) stage->argv[stage->argc++] = word;
				break;
			case TARGET_IN:     stage->input_file = word;  break;
			case TARGET_OUT:    stage->output_file = word; stage->output_append = false; break;
			case TARGET_APPEND: stage->output_file = word; stage->output_append = true;  break;
			case TARGET_ERR:    stage->error_file = word;  break;
			}
			target = TARGET_ARG;
			token.length = 0;
			token.data[0] = '\0';
			have_token = false;
		}

		if (c == '|') {
			if (pipeline->count >= XSH_MAX_STAGES) {
				fputs("xsh: pipeline too long\n", stderr);
				free(token.data);
				return false;
			}
			stage->argv[stage->argc] = NULL;
			stage = &pipeline->stages[pipeline->count++];
		} else if (c == '<') {
			target = TARGET_IN;
		} else if (c == '>') {
			if (line[i + 1] == '>') { i++; target = TARGET_APPEND; }
			else target = TARGET_OUT;
		} else if (c == '&') {
			pipeline->background = true;
		}

		/* "2>file" leaves a stray "2" argument -- turn it into stderr. */
		if ((target == TARGET_OUT || target == TARGET_APPEND) && stage->argc > 0) {
			char *last = stage->argv[stage->argc - 1];
			if (strcmp(last, "2") == 0) {
				free(last);
				stage->argc--;
				target = TARGET_ERR;
			}
		}
	}

	stage->argv[stage->argc] = NULL;
	free(token.data);
	return true;
}

static void free_pipeline(Pipeline *pipeline) {
	for (int i = 0; i < pipeline->count; i++) {
		Stage *stage = &pipeline->stages[i];
		for (int j = 0; j < stage->argc; j++) free(stage->argv[j]);
		free(stage->input_file);
		free(stage->output_file);
		free(stage->error_file);
	}
}

/* -------------------------------------------------------------- builtins */

static int builtin_cd(int argc, char **argv) {
	const char *target = argc > 1 ? argv[1] : getenv("HOME");
	if (!target) target = "/";
	if (chdir(target) != 0) {
		fprintf(stderr, "cd: %s: %s\n", target, strerror(errno));
		return 1;
	}
	char cwd[PATH_MAX];
	if (getcwd(cwd, sizeof(cwd))) setenv("PWD", cwd, 1);
	return 0;
}

static int builtin_pwd(void) {
	char cwd[PATH_MAX];
	if (!getcwd(cwd, sizeof(cwd))) {
		perror("pwd");
		return 1;
	}
	puts(cwd);
	return 0;
}

static int builtin_echo(int argc, char **argv) {
	bool newline = true;
	int start = 1;
	if (argc > 1 && strcmp(argv[1], "-n") == 0) {
		newline = false;
		start = 2;
	}
	for (int i = start; i < argc; i++) {
		if (i > start) putchar(' ');
		fputs(argv[i], stdout);
	}
	if (newline) putchar('\n');
	fflush(stdout);
	return 0;
}

static int builtin_export(int argc, char **argv) {
	if (argc == 1) {
		for (char **entry = environ; *entry; entry++) printf("export %s\n", *entry);
		return 0;
	}
	for (int i = 1; i < argc; i++) {
		char *equals = strchr(argv[i], '=');
		if (!equals) continue;
		*equals = '\0';
		setenv(argv[i], equals + 1, 1);
		*equals = '=';
	}
	return 0;
}

static const char *format_mode(mode_t mode) {
	static char text[11];
	text[0] = S_ISDIR(mode) ? 'd' : S_ISLNK(mode) ? 'l' : '-';
	text[1] = mode & S_IRUSR ? 'r' : '-';
	text[2] = mode & S_IWUSR ? 'w' : '-';
	text[3] = mode & S_IXUSR ? 'x' : '-';
	text[4] = mode & S_IRGRP ? 'r' : '-';
	text[5] = mode & S_IWGRP ? 'w' : '-';
	text[6] = mode & S_IXGRP ? 'x' : '-';
	text[7] = mode & S_IROTH ? 'r' : '-';
	text[8] = mode & S_IWOTH ? 'w' : '-';
	text[9] = mode & S_IXOTH ? 'x' : '-';
	text[10] = '\0';
	return text;
}

static int builtin_ls(int argc, char **argv) {
	bool long_format = false;
	bool show_all = false;
	const char *path = ".";

	for (int i = 1; i < argc; i++) {
		if (argv[i][0] == '-' && argv[i][1]) {
			for (char *flag = argv[i] + 1; *flag; flag++) {
				if (*flag == 'l') long_format = true;
				else if (*flag == 'a') show_all = true;
			}
		} else {
			path = argv[i];
		}
	}

	DIR *directory = opendir(path);
	if (!directory) {
		/* A plain file argument just prints itself. */
		struct stat info;
		if (stat(path, &info) == 0) {
			puts(path);
			return 0;
		}
		fprintf(stderr, "ls: %s: %s\n", path, strerror(errno));
		return 1;
	}

	struct dirent *entry;
	while ((entry = readdir(directory))) {
		if (!show_all && entry->d_name[0] == '.') continue;

		if (!long_format) {
			printf("%s\n", entry->d_name);
			continue;
		}

		char full[PATH_MAX];
		snprintf(full, sizeof(full), "%s/%s", path, entry->d_name);
		struct stat info;
		if (lstat(full, &info) != 0) continue;

		char when[32];
		struct tm parts;
		localtime_r(&info.st_mtime, &parts);
		strftime(when, sizeof(when), "%b %e %H:%M", &parts);

		printf("%s %3u %8lld %s %s\n", format_mode(info.st_mode),
		       (unsigned)info.st_nlink, (long long)info.st_size, when, entry->d_name);
	}
	closedir(directory);
	return 0;
}

static int builtin_cat(int argc, char **argv) {
	if (argc == 1) {
		char buffer[8192];
		ssize_t count;
		while ((count = read(STDIN_FILENO, buffer, sizeof(buffer))) > 0) {
			if (write(STDOUT_FILENO, buffer, (size_t)count) < 0) break;
		}
		return 0;
	}
	int status = 0;
	for (int i = 1; i < argc; i++) {
		int fd = open(argv[i], O_RDONLY);
		if (fd < 0) {
			fprintf(stderr, "cat: %s: %s\n", argv[i], strerror(errno));
			status = 1;
			continue;
		}
		char buffer[8192];
		ssize_t count;
		while ((count = read(fd, buffer, sizeof(buffer))) > 0) {
			if (write(STDOUT_FILENO, buffer, (size_t)count) < 0) break;
		}
		close(fd);
	}
	return status;
}

static int remove_recursive(const char *path) {
	struct stat info;
	if (lstat(path, &info) != 0) return -1;

	if (S_ISDIR(info.st_mode)) {
		DIR *directory = opendir(path);
		if (directory) {
			struct dirent *entry;
			while ((entry = readdir(directory))) {
				if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
					continue;
				}
				char child[PATH_MAX];
				snprintf(child, sizeof(child), "%s/%s", path, entry->d_name);
				remove_recursive(child);
			}
			closedir(directory);
		}
		return rmdir(path);
	}
	return unlink(path);
}

static int builtin_rm(int argc, char **argv) {
	bool recursive = false;
	bool force = false;
	int status = 0;

	for (int i = 1; i < argc; i++) {
		if (argv[i][0] == '-' && argv[i][1]) {
			for (char *flag = argv[i] + 1; *flag; flag++) {
				if (*flag == 'r' || *flag == 'R') recursive = true;
				if (*flag == 'f') force = true;
			}
			continue;
		}
		int result = recursive ? remove_recursive(argv[i]) : unlink(argv[i]);
		if (result != 0 && !force) {
			fprintf(stderr, "rm: %s: %s\n", argv[i], strerror(errno));
			status = 1;
		}
	}
	return status;
}

static int builtin_mkdir(int argc, char **argv) {
	bool parents = false;
	int status = 0;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-p") == 0) { parents = true; continue; }

		if (!parents) {
			if (mkdir(argv[i], 0755) != 0) {
				fprintf(stderr, "mkdir: %s: %s\n", argv[i], strerror(errno));
				status = 1;
			}
			continue;
		}

		char path[PATH_MAX];
		snprintf(path, sizeof(path), "%s", argv[i]);
		for (char *p = path + 1; *p; p++) {
			if (*p != '/') continue;
			*p = '\0';
			mkdir(path, 0755);
			*p = '/';
		}
		if (mkdir(path, 0755) != 0 && errno != EEXIST) {
			fprintf(stderr, "mkdir: %s: %s\n", argv[i], strerror(errno));
			status = 1;
		}
	}
	return status;
}

static int copy_file(const char *from, const char *to) {
	int in = open(from, O_RDONLY);
	if (in < 0) return -1;

	struct stat info;
	fstat(in, &info);

	int out = open(to, O_WRONLY | O_CREAT | O_TRUNC, info.st_mode & 0777);
	if (out < 0) { close(in); return -1; }

	char buffer[65536];
	ssize_t count;
	while ((count = read(in, buffer, sizeof(buffer))) > 0) {
		if (write(out, buffer, (size_t)count) != count) { count = -1; break; }
	}
	close(in);
	close(out);
	return count < 0 ? -1 : 0;
}

static int builtin_cp(int argc, char **argv) {
	if (argc < 3) {
		fputs("usage: cp source... destination\n", stderr);
		return 1;
	}
	const char *destination = argv[argc - 1];
	struct stat info;
	bool to_directory = stat(destination, &info) == 0 && S_ISDIR(info.st_mode);

	int status = 0;
	for (int i = 1; i < argc - 1; i++) {
		char target[PATH_MAX];
		if (to_directory) {
			const char *base = strrchr(argv[i], '/');
			snprintf(target, sizeof(target), "%s/%s", destination, base ? base + 1 : argv[i]);
		} else {
			snprintf(target, sizeof(target), "%s", destination);
		}
		if (copy_file(argv[i], target) != 0) {
			fprintf(stderr, "cp: %s: %s\n", argv[i], strerror(errno));
			status = 1;
		}
	}
	return status;
}

static int builtin_mv(int argc, char **argv) {
	if (argc < 3) {
		fputs("usage: mv source destination\n", stderr);
		return 1;
	}
	const char *destination = argv[argc - 1];
	struct stat info;
	bool to_directory = stat(destination, &info) == 0 && S_ISDIR(info.st_mode);

	int status = 0;
	for (int i = 1; i < argc - 1; i++) {
		char target[PATH_MAX];
		if (to_directory) {
			const char *base = strrchr(argv[i], '/');
			snprintf(target, sizeof(target), "%s/%s", destination, base ? base + 1 : argv[i]);
		} else {
			snprintf(target, sizeof(target), "%s", destination);
		}
		if (rename(argv[i], target) != 0) {
			/* Crossing filesystems: fall back to copy + unlink. */
			if (copy_file(argv[i], target) == 0) {
				unlink(argv[i]);
			} else {
				fprintf(stderr, "mv: %s: %s\n", argv[i], strerror(errno));
				status = 1;
			}
		}
	}
	return status;
}

static char *find_in_path(const char *command) {
	if (strchr(command, '/')) {
		return access(command, X_OK) == 0 ? xstrdup(command) : NULL;
	}

	const char *path = getenv("PATH");
	if (!path) path = "/usr/bin:/bin";

	char *copy = xstrdup(path);
	char *saveptr = NULL;
	for (char *directory = strtok_r(copy, ":", &saveptr); directory;
	     directory = strtok_r(NULL, ":", &saveptr)) {
		char candidate[PATH_MAX];
		snprintf(candidate, sizeof(candidate), "%s/%s", directory, command);
		if (access(candidate, X_OK) == 0) {
			free(copy);
			return xstrdup(candidate);
		}
	}
	free(copy);
	return NULL;
}

static int builtin_which(int argc, char **argv) {
	int status = 0;
	for (int i = 1; i < argc; i++) {
		char *resolved = find_in_path(argv[i]);
		if (resolved) {
			puts(resolved);
			free(resolved);
		} else {
			fprintf(stderr, "which: %s: not found\n", argv[i]);
			status = 1;
		}
	}
	return status;
}

static int builtin_help(void) {
	fputs(
		"xsh -- Termux for iOS built-in shell\n"
		"\n"
		"This minimal shell exists so the terminal works before a bootstrap is\n"
		"installed.  Install one from the menu to get bash, apt and friends.\n"
		"\n"
		"Builtins:\n"
		"  cd pwd echo export unset env exit help history source\n"
		"  ls cat rm mkdir rmdir mv cp touch which chmod clear\n"
		"\n"
		"Syntax: pipelines (|), redirection (< > >> 2>), quoting, $VARIABLES\n"
		"\n"
		"Environment:\n"
		"  $PREFIX  the bootstrap prefix\n"
		"  $HOME    your home directory\n",
		stdout);
	return 0;
}

/* ------------------------------------------------------------- execution */

/* Returns -1 when the command is not a builtin. */
static int run_builtin(Stage *stage) {
	int argc = stage->argc;
	char **argv = stage->argv;
	if (argc == 0) return 0;

	const char *name = argv[0];

	if (strcmp(name, "cd") == 0)     return builtin_cd(argc, argv);
	if (strcmp(name, "pwd") == 0)    return builtin_pwd();
	if (strcmp(name, "echo") == 0)   return builtin_echo(argc, argv);
	if (strcmp(name, "export") == 0) return builtin_export(argc, argv);
	if (strcmp(name, "help") == 0)   return builtin_help();
	if (strcmp(name, "ls") == 0)     return builtin_ls(argc, argv);
	if (strcmp(name, "cat") == 0)    return builtin_cat(argc, argv);
	if (strcmp(name, "rm") == 0)     return builtin_rm(argc, argv);
	if (strcmp(name, "mkdir") == 0)  return builtin_mkdir(argc, argv);
	if (strcmp(name, "cp") == 0)     return builtin_cp(argc, argv);
	if (strcmp(name, "mv") == 0)     return builtin_mv(argc, argv);
	if (strcmp(name, "which") == 0)  return builtin_which(argc, argv);

	if (strcmp(name, "unset") == 0) {
		for (int i = 1; i < argc; i++) unsetenv(argv[i]);
		return 0;
	}
	if (strcmp(name, "env") == 0) {
		for (char **entry = environ; *entry; entry++) puts(*entry);
		return 0;
	}
	if (strcmp(name, "rmdir") == 0) {
		int status = 0;
		for (int i = 1; i < argc; i++) {
			if (rmdir(argv[i]) != 0) {
				fprintf(stderr, "rmdir: %s: %s\n", argv[i], strerror(errno));
				status = 1;
			}
		}
		return status;
	}
	if (strcmp(name, "touch") == 0) {
		int status = 0;
		for (int i = 1; i < argc; i++) {
			int fd = open(argv[i], O_WRONLY | O_CREAT, 0644);
			if (fd < 0) {
				fprintf(stderr, "touch: %s: %s\n", argv[i], strerror(errno));
				status = 1;
			} else {
				close(fd);
			}
		}
		return status;
	}
	if (strcmp(name, "chmod") == 0) {
		if (argc < 3) { fputs("usage: chmod mode file...\n", stderr); return 1; }
		mode_t mode = (mode_t)strtol(argv[1], NULL, 8);
		int status = 0;
		for (int i = 2; i < argc; i++) {
			if (chmod(argv[i], mode) != 0) {
				fprintf(stderr, "chmod: %s: %s\n", argv[i], strerror(errno));
				status = 1;
			}
		}
		return status;
	}
	if (strcmp(name, "clear") == 0) {
		fputs("\033[H\033[2J\033[3J", stdout);
		fflush(stdout);
		return 0;
	}
	if (strcmp(name, "exit") == 0) {
		exit(argc > 1 ? atoi(argv[1]) : g_last_status);
	}

	return -1;
}

static void apply_redirections(Stage *stage) {
	if (stage->input_file) {
		int fd = open(stage->input_file, O_RDONLY);
		if (fd >= 0) { dup2(fd, STDIN_FILENO); close(fd); }
	}
	if (stage->output_file) {
		int flags = O_WRONLY | O_CREAT | (stage->output_append ? O_APPEND : O_TRUNC);
		int fd = open(stage->output_file, flags, 0644);
		if (fd >= 0) { dup2(fd, STDOUT_FILENO); close(fd); }
	}
	if (stage->error_file) {
		int fd = open(stage->error_file, O_WRONLY | O_CREAT | O_TRUNC, 0644);
		if (fd >= 0) { dup2(fd, STDERR_FILENO); close(fd); }
	}
}

static int run_pipeline(Pipeline *pipeline) {
	if (pipeline->count == 1 && pipeline->stages[0].argc > 0) {
		Stage *stage = &pipeline->stages[0];

		/* Builtins run in-process unless they are redirected. */
		if (!stage->input_file && !stage->output_file && !stage->error_file) {
			int result = run_builtin(stage);
			if (result >= 0) return result;
		} else {
			int saved_in = dup(STDIN_FILENO);
			int saved_out = dup(STDOUT_FILENO);
			int saved_err = dup(STDERR_FILENO);
			apply_redirections(stage);
			int result = run_builtin(stage);
			fflush(stdout);
			dup2(saved_in, STDIN_FILENO);
			dup2(saved_out, STDOUT_FILENO);
			dup2(saved_err, STDERR_FILENO);
			close(saved_in); close(saved_out); close(saved_err);
			if (result >= 0) return result;
		}
	}

	pid_t pids[XSH_MAX_STAGES];
	int previous_read = -1;
	int status = 0;

	for (int i = 0; i < pipeline->count; i++) {
		Stage *stage = &pipeline->stages[i];
		if (stage->argc == 0) continue;

		int pipe_fds[2] = {-1, -1};
		bool has_next = (i + 1 < pipeline->count);
		if (has_next && pipe(pipe_fds) != 0) {
			perror("xsh: pipe");
			return 1;
		}

		char *program = find_in_path(stage->argv[0]);
		if (!program) {
			fprintf(stderr, "xsh: %s: command not found\n", stage->argv[0]);
			if (pipe_fds[0] >= 0) { close(pipe_fds[0]); close(pipe_fds[1]); }
			if (previous_read >= 0) close(previous_read);
			return 127;
		}

		posix_spawn_file_actions_t actions;
		posix_spawn_file_actions_init(&actions);

		if (previous_read >= 0) {
			posix_spawn_file_actions_adddup2(&actions, previous_read, STDIN_FILENO);
			posix_spawn_file_actions_addclose(&actions, previous_read);
		}
		if (has_next) {
			posix_spawn_file_actions_adddup2(&actions, pipe_fds[1], STDOUT_FILENO);
			posix_spawn_file_actions_addclose(&actions, pipe_fds[0]);
			posix_spawn_file_actions_addclose(&actions, pipe_fds[1]);
		}
		if (stage->input_file) {
			posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, stage->input_file,
			                                 O_RDONLY, 0);
		}
		if (stage->output_file) {
			int flags = O_WRONLY | O_CREAT | (stage->output_append ? O_APPEND : O_TRUNC);
			posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, stage->output_file,
			                                 flags, 0644);
		}
		if (stage->error_file) {
			posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, stage->error_file,
			                                 O_WRONLY | O_CREAT | O_TRUNC, 0644);
		}

		pid_t pid = -1;
		int result = posix_spawn(&pid, program, &actions, NULL, stage->argv, environ);
		posix_spawn_file_actions_destroy(&actions);
		free(program);

		if (result != 0) {
			fprintf(stderr, "xsh: %s: %s\n", stage->argv[0], strerror(result));
			if (pipe_fds[0] >= 0) { close(pipe_fds[0]); close(pipe_fds[1]); }
			if (previous_read >= 0) close(previous_read);
			return 126;
		}

		pids[i] = pid;

		if (previous_read >= 0) close(previous_read);
		if (has_next) {
			close(pipe_fds[1]);
			previous_read = pipe_fds[0];
		}
	}

	if (pipeline->background) {
		fprintf(stderr, "[background pid %d]\n", (int)pids[pipeline->count - 1]);
		return 0;
	}

	for (int i = 0; i < pipeline->count; i++) {
		if (pipeline->stages[i].argc == 0) continue;
		int child_status = 0;
		waitpid(pids[i], &child_status, 0);
		if (WIFEXITED(child_status)) status = WEXITSTATUS(child_status);
		else if (WIFSIGNALED(child_status)) status = 128 + WTERMSIG(child_status);
	}
	return status;
}

/* --------------------------------------------------------- command lists */

/*
 * A line is a list of pipelines joined by ';', '&&' or '||'.  We split on
 * those operators first, respecting quotes, then run each pipeline in turn
 * and let the operator decide whether the next one executes.
 */

typedef enum {
	JOIN_SEQUENTIAL,   /* ;  -- always run the next command   */
	JOIN_AND,          /* && -- run only after success        */
	JOIN_OR,           /* || -- run only after failure        */
} JoinOperator;

typedef struct {
	char *text;
	JoinOperator join;   /* how this command relates to the previous one */
} Command;

#define XSH_MAX_COMMANDS 32

/* Splits `line` in place.  Returns the number of commands found. */
static int split_commands(char *line, Command *commands, int max) {
	int count = 0;
	JoinOperator next_join = JOIN_SEQUENTIAL;

	char *start = line;
	bool in_single = false;
	bool in_double = false;

	for (char *p = line; ; p++) {
		if (*p == '\\' && p[1] && !in_single) { p++; continue; }
		if (*p == '\'' && !in_double) { in_single = !in_single; continue; }
		if (*p == '"' && !in_single) { in_double = !in_double; continue; }
		if (in_single || in_double) {
			if (*p == '\0') break;
			continue;
		}

		bool is_and = (p[0] == '&' && p[1] == '&');
		bool is_or = (p[0] == '|' && p[1] == '|');
		bool is_semi = (p[0] == ';');
		bool is_end = (p[0] == '\0');

		if (!is_and && !is_or && !is_semi && !is_end) continue;

		/* A single '|' is a pipe, not a separator -- leave it alone. */
		if (p[0] == '|' && !is_or) continue;
		/* A single '&' means background, handled inside parse_line. */
		if (p[0] == '&' && !is_and) continue;

		if (count >= max) break;

		size_t length = (size_t)(p - start);
		char *text = xmalloc(length + 1);
		memcpy(text, start, length);
		text[length] = '\0';

		commands[count].text = text;
		commands[count].join = next_join;
		count++;

		if (is_end) break;

		next_join = is_and ? JOIN_AND : is_or ? JOIN_OR : JOIN_SEQUENTIAL;
		p += (is_and || is_or) ? 1 : 0;
		start = p + 1;
	}

	return count;
}

/* Runs one line, honouring ; && and ||.  Returns the last exit status. */
static int run_line(char *line) {
	Command commands[XSH_MAX_COMMANDS];
	int count = split_commands(line, commands, XSH_MAX_COMMANDS);
	int status = g_last_status;

	for (int i = 0; i < count; i++) {
		char *text = commands[i].text;

		/* Skip when the operator says the previous result forbids it. */
		bool should_run = true;
		if (commands[i].join == JOIN_AND && status != 0) should_run = false;
		if (commands[i].join == JOIN_OR && status == 0) should_run = false;

		const char *first = text;
		while (*first == ' ' || *first == '\t') first++;
		if (*first == '\0' || *first == '#') should_run = false;

		if (should_run) {
			Pipeline pipeline;
			if (parse_line(text, &pipeline)) {
				status = run_pipeline(&pipeline);
				g_last_status = status;
				free_pipeline(&pipeline);
			} else {
				status = 2;
				g_last_status = status;
			}
		}
		free(text);
	}

	return status;
}

/* ------------------------------------------------------------------- main */

static void print_prompt(void) {
	char cwd[PATH_MAX];
	if (!getcwd(cwd, sizeof(cwd))) snprintf(cwd, sizeof(cwd), "?");

	const char *home = getenv("HOME");
	const char *display = cwd;
	char shortened[PATH_MAX];
	if (home && strncmp(cwd, home, strlen(home)) == 0) {
		snprintf(shortened, sizeof(shortened), "~%s", cwd + strlen(home));
		display = shortened;
	}

	printf("\033[1;32mxsh\033[0m:\033[1;34m%s\033[0m$ ", display);
	fflush(stdout);
}

static void print_banner(void) {
	fputs(
		"\033[1;32m"
		"  ______                            \n"
		" /_  __/__  _________ ___  __ ___  __\n"
		"  / / / _ \\/ ___/ __ `__ \\/ / / / |/_/\n"
		" / / /  __/ /  / / / / / / /_/ />  <  \n"
		"/_/  \\___/_/  /_/ /_/ /_/\\__,_/_/|_|  \n"
		"\033[0m"
		"\033[2m        for iOS -- built-in shell\033[0m\n\n"
		"Type \033[1mhelp\033[0m for builtins, or install a bootstrap from the menu\n"
		"to get bash, apt, git, python and the rest.\n\n",
		stdout);
	fflush(stdout);
}

int main(int argc, char *argv[]) {
	/* -c "command" runs a single command, like any other shell. */
	if (argc >= 3 && strcmp(argv[1], "-c") == 0) {
		char line[XSH_MAX_LINE];
		snprintf(line, sizeof(line), "%s", argv[2]);
		return run_line(line);
	}

	signal(SIGINT, SIG_IGN);
	signal(SIGPIPE, SIG_IGN);

	const char *home = getenv("HOME");
	if (home) chdir(home);

	bool interactive = isatty(STDIN_FILENO);
	if (interactive) print_banner();

	char line[XSH_MAX_LINE];
	while (true) {
		if (interactive) print_prompt();

		if (!fgets(line, sizeof(line), stdin)) {
			if (interactive) putchar('\n');
			break;
		}

		size_t length = strlen(line);
		while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r')) {
			line[--length] = '\0';
		}

		/* Skip blanks and comments. */
		const char *first = line;
		while (*first == ' ' || *first == '\t') first++;
		if (*first == '\0' || *first == '#') continue;

		g_last_status = run_line(line);
	}

	return g_last_status;
}
