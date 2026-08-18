#include <errno.h>
#include <mach-o/loader.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int hex_value(char value) {
  if (value >= '0' && value <= '9')
    return value - '0';
  if (value >= 'a' && value <= 'f')
    return value - 'a' + 10;
  if (value >= 'A' && value <= 'F')
    return value - 'A' + 10;
  return -1;
}

static int parse_uuid(const char *text, uint8_t output[16]) {
  if (strlen(text) != 32)
    return -1;
  for (size_t index = 0; index < 16; index++) {
    int high = hex_value(text[index * 2]);
    int low = hex_value(text[index * 2 + 1]);
    if (high < 0 || low < 0)
      return -1;
    output[index] = (uint8_t)((high << 4) | low);
  }
  return 0;
}

static int normalize(const char *path, const uint8_t uuid[16]) {
  FILE *file = fopen(path, "r+b");
  if (file == NULL) {
    fprintf(stderr, "normalize-macho: %s: %s\n", path, strerror(errno));
    return 1;
  }

  struct mach_header_64 header;
  if (fread(&header, sizeof(header), 1, file) != 1 ||
      header.magic != MH_MAGIC_64) {
    fprintf(stderr, "normalize-macho: unsupported Mach-O header: %s\n", path);
    fclose(file);
    return 1;
  }

  for (uint32_t index = 0; index < header.ncmds; index++) {
    long offset = ftell(file);
    struct load_command command;
    if (offset < 0 || fread(&command, sizeof(command), 1, file) != 1 ||
        command.cmdsize < sizeof(command)) {
      fprintf(stderr, "normalize-macho: invalid load command: %s\n", path);
      fclose(file);
      return 1;
    }

    if (command.cmd == LC_UUID) {
      long uuid_offset = offset + (long)offsetof(struct uuid_command, uuid);
      if (fseek(file, uuid_offset, SEEK_SET) != 0 ||
          fwrite(uuid, 16, 1, file) != 1 || fflush(file) != 0) {
        fprintf(stderr, "normalize-macho: could not write UUID: %s\n", path);
        fclose(file);
        return 1;
      }
      fclose(file);
      return 0;
    }

    if (fseek(file, offset + command.cmdsize, SEEK_SET) != 0) {
      fprintf(stderr, "normalize-macho: invalid command offset: %s\n", path);
      fclose(file);
      return 1;
    }
  }

  fprintf(stderr, "normalize-macho: LC_UUID is missing: %s\n", path);
  fclose(file);
  return 1;
}

int main(int argc, char **argv) {
  uint8_t uuid[16];
  if (argc != 3 || parse_uuid(argv[2], uuid) != 0) {
    fprintf(stderr, "usage: normalize-macho FILE UUID_HEX\n");
    return 2;
  }
  return normalize(argv[1], uuid);
}
