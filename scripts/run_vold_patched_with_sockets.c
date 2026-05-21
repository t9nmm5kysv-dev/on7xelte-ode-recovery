#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static void make_socket(const char *name) {
    char path[256];
    snprintf(path, sizeof(path), "/dev/socket/%s", name);
    unlink(path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); exit(1); }
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) { perror(path); exit(1); }
    chmod(path, 0666);
    if (listen(fd, 16) < 0) { perror("listen"); exit(1); }
    char envname[128];
    char envval[32];
    snprintf(envname, sizeof(envname), "ANDROID_SOCKET_%s", name);
    snprintf(envval, sizeof(envval), "%d", fd);
    setenv(envname, envval, 1);
    fprintf(stderr, "%s=%s path=%s\n", envname, envval, path);
}

int main(void) {
    mkdir("/dev/socket", 0777);
    make_socket("vold");
    make_socket("cryptd");
    make_socket("frigate");
    make_socket("epm");
    make_socket("ppm");
    make_socket("dir_enc_report");
    setenv("LD_LIBRARY_PATH", "/vendor/lib:/system/vendor/lib:/system/lib:/sbin", 1);
    setenv("ANDROID_ROOT", "/system", 1);
    setenv("ANDROID_DATA", "/data", 1);
    setenv("PATH", "/system/bin:/sbin:/bin", 1);
    char *argv[] = {
        "/tmp/vold_patched",
        "--blkid_context=u:r:blkid:s0",
        "--blkid_untrusted_context=u:r:blkid_untrusted:s0",
        "--fsck_context=u:r:fsck:s0",
        "--fsck_untrusted_context=u:r:fsck_untrusted:s0",
        NULL
    };
    execv(argv[0], argv);
    perror("execv /tmp/vold_patched");
    return 127;
}
