# SPDX-License-Identifier: Apache-2.0
#
# A Mix project beside the rebar3 one, for a single reason: elixir_make's
# precompilation flow is how a NIF gets built once and downloaded everywhere
# after, and it is a Mix compiler. rebar3 still builds this repository the way
# it always did; nothing here replaces it.
#
# What the flow buys. Without it every desk and every CI job that wants egit
# compiles C++ against libgit2 first, which on Windows means having
# llvm-mingw and a pixi environment before you can read a HEAD. With it, the
# tagged build runs once per platform in Actions, the artefacts are attached
# to the release, and a consumer downloads the one matching its NIF version
# and target triple.
#
#   mix elixir_make.precompile                 # build the artefact for this target
#   mix elixir_make.checksum --all             # after the release, write checksum.exs
#
# THE VERSION CARRIES THE FORK. Upstream tags v0.2.1 and so would this, which
# would put two different builds behind one name in tags, release titles and
# every artefact filename. `0.2.1-vsekai.1` says which is which everywhere it
# appears: egit 0.2.1 plus the patches here. The cost is that semver sorts a
# prerelease below the release it names, so this reads as older than upstream
# 0.2.1 to a range resolver; nothing resolves a range across both forks, and a
# name that cannot be confused is worth more than an ordering nobody consults.
#
# checksum.exs is generated from the published artefacts and goes into the Hex
# package, where it is mandatory - a consumer verifies each download against
# it. It is not tracked in git, because it describes a release that exists
# rather than a source tree.

defmodule Egit.MixProject do
  use Mix.Project

  @version "0.2.1-vsekai.1"
  @source_url "https://github.com/V-Sekai-fire/egit"

  def project do
    [
      app: :egit,
      version: @version,
      language: :erlang,
      compilers: [:elixir_make] ++ Mix.compilers(),
      deps: deps(),
      package: package(),
      description: "Erlang NIF interface to libgit2",

      # The build is cmake, not make. elixir_make would otherwise run `make`
      # on Unix and `nmake` on Windows, and this repository needs neither.
      make_executable: "cmake",
      make_args: ["-P", "build.cmake"],
      make_cwd: __DIR__,

      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_url:
        "#{@source_url}/releases/download/v#{@version}/@{artefact_filename}",
      # The shared library is priv/git.<ext> while the app is egit, so the
      # filename has to be said out loud.
      make_precompiler_filename: "git",
      make_precompiler_priv_paths: ["git.*"],
      make_precompiler_nif_versions: [versions: ["2.16", "2.17", "2.18"]],

      # cc_precompiler picks the compiler for a target itself and ignores CC
      # and CXX in the environment, so on Windows it looked for an MSVC
      # toolchain and stopped at "Compiler not found for
      # x86_64-windows-msvc". The Windows build here is llvm-mingw, named
      # here rather than exported.
      cc_precompiler: [
        compilers: %{
          {:win32, :nt} => %{
            :include_default_ones => false,
            "x86_64-windows-msvc" => {"clang", "clang++"}
          },
          {:unix, :darwin} => %{:include_default_ones => true},
          {:unix, :linux} => %{:include_default_ones => true}
        }
      ]
    ]
  end

  def application, do: [extra_applications: []]

  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false},
      {:cc_precompiler, "~> 0.1", runtime: false}
    ]
  end

  defp package do
    [
      files: [
        "src",
        "c_src",
        "CMakeLists.txt",
        "build.cmake",
        "mix.exs",
        "rebar.config",
        "checksum.exs",
        "README.md",
        "LICENSE"
      ],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
