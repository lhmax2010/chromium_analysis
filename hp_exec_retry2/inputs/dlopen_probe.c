#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv) {
  int i;
  for (i = 1; i < argc; ++i) {
    void *handle = dlopen(argv[i], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
      fprintf(stderr, "[DLOPEN-FAIL] %s: %s\n", argv[i], dlerror());
      return 10 + i;
    }
    printf("[DLOPEN-OK] %s\n", argv[i]);
  }
  printf("[DLOPEN-ALL-OK] count=%d\n", argc - 1);
  return 0;
}
