# SPDX-License-Identifier: Apache-2.0

defmodule Egit.MixProject do
  use Mix.Project

  @version "0.2.1-vsekai.2.dev"
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

      make_executable: "cmake",
      make_args: ["-P", "build.cmake"],
      make_cwd: __DIR__,

      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_url:
        "#{@source_url}/releases/download/v#{@version}/@{artefact_filename}",
      make_precompiler_filename: "git",
      make_precompiler_priv_paths: ["git.*", "egit.sigs"],
      make_precompiler_nif_versions: [versions: ["2.16", "2.17", "2.18"]],

      # cc_precompiler picks the compiler itself and ignores CC/CXX.
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
