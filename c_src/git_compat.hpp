// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdlib>
#include <cstring>

// basename(3) and strndup(3) are POSIX; MSVC ships neither.
inline const char* egit_basename(const char* path)
{
  const char* base = path;
  for (const char* p = path; *p; ++p)
    if (*p == '/' || *p == '\\')
      base = p + 1;
  return base;
}

inline char* egit_strndup(const char* src, size_t n)
{
  size_t len  = ::strnlen(src, n);
  char*  copy = static_cast<char*>(::malloc(len + 1));
  if (copy) {
    ::memcpy(copy, src, len);
    copy[len] = '\0';
  }
  return copy;
}
