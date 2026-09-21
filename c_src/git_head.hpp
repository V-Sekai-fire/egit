// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <git2/repository.h>
#include <git2/branch.h>

ERL_NIF_TERM lg2_head(ErlNifEnv* env, git_repository* repo)
{
  git_reference* raw = nullptr;
  int rc = git_repository_head(&raw, repo);

  if (rc == GIT_EUNBORNBRANCH) {
    git_reference* sym = nullptr;
    if (git_reference_lookup(&sym, repo, "HEAD") != GIT_OK) [[unlikely]]
      return make_git_error(env, "Could not read HEAD");
    SmartPtr<git_reference> ref(git_reference_free, sym);
    const char* target = git_reference_symbolic_target(sym);
    const char* name   = target && strncmp(target, "refs/heads/", 11) == 0
                       ? target + 11 : target;
    return enif_make_tuple3(env, ATOM_BRANCH,
                            make_binary(env, name ? name : ""), ATOM_UNBORN);
  }

  if (rc == GIT_ENOTFOUND) [[unlikely]]
    return make_git_error(env, "No HEAD in this repository");
  if (rc != GIT_OK) [[unlikely]]
    return make_git_error(env, "Could not read HEAD");

  SmartPtr<git_reference> ref(git_reference_free, raw);

  if (git_repository_head_detached(repo) == 1) {
    const git_oid* oid = git_reference_target(raw);
    return enif_make_tuple2(env, ATOM_DETACHED,
                            make_binary(env, oid_to_str(*oid, GIT_OID_SHA1_HEXSIZE)));
  }

  const char* shorthand = git_reference_shorthand(raw);
  return enif_make_tuple2(env, ATOM_BRANCH,
                          make_binary(env, shorthand ? shorthand : ""));
}
