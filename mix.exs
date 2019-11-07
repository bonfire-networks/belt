defmodule Belt.Mixfile do
  use Mix.Project

  def project do
    [app: :belt,
     version: "0.5.0",
     elixir: "~> 1.9",
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     test_coverage: [tool: ExCoveralls],
     deps: deps(),
     dialyzer: [plt_add_apps: [:ssh, :observer]],

     #Hex
     description: description(),
     package: package(),

     #Docs
     name: "Belt",
     docs: [
      canonical: "http://hexdocs.pm/belt",
      source_url: "https://bitbucket.org/pentacent/belt",
      homepage_url: "https://bitbucket.org/pentacent/belt",
      extras: ["guides/getting-started.md"]
     ]
    ]
  end

  def application do
    [mod: {Belt.Application, []},
     extra_applications: [:logger]]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/shared"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [{:gen_stage, "~> 0.12"},
     {:ex_doc, "~> 0.19", only: :dev, runtime: false},
     {:coverex, "~> 1.4", only: :test},
     {:excoveralls, "~> 0.6", only: :test},
     {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
     {:ex_aws, "~> 2.1", optional: true},
     {:ex_aws_s3, "~> 2.0", optional: true},
     {:sweet_xml, "~> 0.6", optional: true},
     {:hackney, "~> 1.9", optional: true},
     {:ecto, "~> 2.1 or ~> 3.0", optional: true}
   ]
  end

  defp package do
    [
      name: :belt,
      files: ["lib", "mix.exs", "README*", "LICENSE*", "test", "config/config.exs"],
      licenses: ["Apache 2", "GNU AGPLv3"],
      links: %{"Bitbucket" => "https://bitbucket.org/pentacent/belt",
               "Issues" => "https://bitbucket.org/pentacent/belt/issues"},
      maintainers: ["Philipp Schmieder"],
    ]
  end

  defp description do
    """
    Extensible Elixir OTP Application for storing files through a unified API.

    Backends currently exist for the local filesystem, SFTP and the Amazon S3 API.
    """
  end
end
