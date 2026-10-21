/* Who is at the desk, and their picture (lock.h): for the door the screen
 * lock shows. In the drawing library, so that the preview can show it too. */

#include "lock.h"
#include "apps.h"

#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

void desk_lock_user(char *login, size_t nl, char *name, size_t nn)
{
	struct passwd *pw = getpwuid(getuid());
	const char *l = pw && pw->pw_name ? pw->pw_name : getenv("USER");
	snprintf(login, nl, "%s", l ? l : "");
	name[0] = '\0';
	if (pw && pw->pw_gecos && pw->pw_gecos[0]) {
		size_t k = strcspn(pw->pw_gecos, ",");
		if (k > 0) {
			snprintf(name, nn, "%.*s", (int)k, pw->pw_gecos);
		}
	}
	if (!name[0]) {
		snprintf(name, nn, "%s", login);
	}
}

static bool is_png(const char *path)
{
	FILE *f = fopen(path, "rbe");
	if (!f) {
		return false;
	}
	unsigned char sig[8] = { 0 };
	size_t n = fread(sig, 1, sizeof sig, f);
	fclose(f);
	static const unsigned char PNG[8] = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
	return n == 8 && !memcmp(sig, PNG, 8);
}

static bool is_svg(const char *path)
{
	FILE *f = fopen(path, "re");
	if (!f) {
		return false;
	}
	char head[512] = "";
	size_t n = fread(head, 1, sizeof head - 1, f);
	fclose(f);
	head[n] = '\0';
	return strstr(head, "<svg") != NULL;
}

/* an SVG into a PNG this size, with whatever is installed (as icons are) */
static bool raster(const char *svg, const char *png, int px)
{
	return desk_svg_raster(svg, png, px) && is_png(png);
}

cairo_surface_t *desk_lock_picture(void)
{
	char path[1024], png[1024];
	const char *home = getenv("HOME");
	const char *cands[4] = { NULL, NULL, NULL, NULL };
	char a[1024] = "", b[1024] = "", c[1024] = "";
	if (home && *home) {
		snprintf(a, sizeof a, "%s/.face", home);
		snprintf(b, sizeof b, "%s/.face.icon", home);
		cands[0] = a;
		cands[1] = b;
	}
	char login[64], name[128];
	desk_lock_user(login, sizeof login, name, sizeof name);
	snprintf(c, sizeof c, "/var/lib/AccountsService/icons/%s", login);
	cands[2] = c;
	for (int i = 0; i < 3; i++) {
		if (!cands[i] || access(cands[i], R_OK) != 0) {
			continue;
		}
		snprintf(path, sizeof path, "%s", cands[i]);
		if (is_svg(path)) {
			const char *cache = getenv("XDG_CACHE_HOME");
			char dir[1024];
			if (cache && *cache) {
				snprintf(dir, sizeof dir, "%s/desk", cache);
			} else if (home && *home) {
				snprintf(dir, sizeof dir, "%s/.cache/desk", home);
			} else {
				continue;
			}
			mkdir(dir, 0755);
			if ((size_t)snprintf(png, sizeof png, "%s/face.png", dir) >= sizeof png
				|| !raster(path, png, 384)) {
				continue;
			}
			snprintf(path, sizeof path, "%s", png);
		}
		if (!is_png(path)) {
			continue;
		}
		cairo_surface_t *s = cairo_image_surface_create_from_png(path);
		if (cairo_surface_status(s) == CAIRO_STATUS_SUCCESS) {
			return s;
		}
		cairo_surface_destroy(s);
	}
	return NULL;
}

