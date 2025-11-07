defmodule Caffeine.MixProject do
  use Mix.Project

  def project do
    [
      app: :caffeine,
      version: "0.0.24",
      elixir: "~> 1.17",
      archives: [mix_gleam: "~> 0.6"],
      compilers: [:gleam] ++ Mix.compilers(),
      erlc_paths: [
        "build/dev/erlang/caffeine_lang/_gleam_artefacts",
        "build/dev/erlang/caffeine_lang/build"
      ],
      erlc_include_path: "build/dev/erlang/caffeine_lang/include",
      erlc_options: [:debug_info, :warn_unused_vars, :warn_unused_import],
      prune_code_paths: false,
      deps: deps(),
      releases: [
        caffeine: [
          steps: [:assemble, &Burrito.wrap/1],
          burrito: [
            targets: [
              macos: [os: :darwin, cpu: :x86_64],
              macos_arm: [os: :darwin, cpu: :aarch64],
              linux: [os: :linux, cpu: :x86_64],
              linux_arm: [os: :linux, cpu: :aarch64],
              win: [os: :windows, cpu: :x86_64]
            ],
            command: "caffeine_lang@caffeine_lang:main()"
          ]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:mix_gleam, "~> 0.6"},
      {:burrito, "~> 1.4"}
    ]
  end
end

