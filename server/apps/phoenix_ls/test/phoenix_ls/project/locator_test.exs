defmodule PhoenixLS.Project.LocatorTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Project.Locator
  alias PhoenixLS.Support.URI, as: SupportURI

  test "locates the nearest Mix project from a nested file URI", context do
    root = fixture_project(context, "plain_project")
    file_path = Path.join([root, "lib", "plain_project.ex"])
    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, "defmodule PlainProject do\nend\n")

    assert {:ok, result} = Locator.locate(SupportURI.path_to_file_uri!(file_path))
    assert result.root_path == root
    assert result.root_uri == SupportURI.path_to_file_uri!(root)
    assert result.mix_exs_path == Path.join(root, "mix.exs")
    assert result.phoenix? == false
    assert result.umbrella_root_path == nil
    assert result.umbrella_root_uri == nil
  end

  test "detects Phoenix dependency from mix.exs AST", context do
    root = fixture_project(context, "phoenix_project", phoenix?: true)
    lib_dir = Path.join(root, "lib")
    File.mkdir_p!(lib_dir)

    assert {:ok, result} = Locator.locate(SupportURI.path_to_file_uri!(lib_dir))
    assert result.root_path == root
    assert result.phoenix? == true
  end

  test "locates umbrella child projects and records umbrella root", context do
    umbrella_root = fixture_project(context, "umbrella")
    child_root = Path.join([umbrella_root, "apps", "shop"])
    write_mix_project!(child_root, phoenix?: true)

    file_path = Path.join([child_root, "lib", "shop_web", "live", "page_live.ex"])
    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, "defmodule ShopWeb.PageLive do\nend\n")

    assert {:ok, result} = Locator.locate(SupportURI.path_to_file_uri!(file_path))
    assert result.root_path == child_root
    assert result.root_uri == SupportURI.path_to_file_uri!(child_root)
    assert result.umbrella_root_path == umbrella_root
    assert result.umbrella_root_uri == SupportURI.path_to_file_uri!(umbrella_root)
    assert result.phoenix? == true
  end

  test "returns error when no Mix project ancestor exists", context do
    dir = tmp_dir(context)
    file_path = Path.join([dir, "lib", "lonely.ex"])
    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, "defmodule Lonely do\nend\n")

    assert Locator.locate(SupportURI.path_to_file_uri!(file_path)) == :error
  end

  test "returns URI conversion errors unchanged" do
    assert Locator.locate("untitled:Untitled-1") ==
             {:error, {:unsupported_uri_scheme, "untitled"}}
  end

  defp fixture_project(context, name, opts \\ []) do
    root = Path.join(tmp_dir(context), name)
    write_mix_project!(root, opts)
    root
  end

  defp write_mix_project!(root, opts) do
    File.mkdir_p!(root)

    deps =
      if Keyword.get(opts, :phoenix?, false) do
        "[{:phoenix, \"~> 1.7\"}]"
      else
        "[]"
      end

    File.write!(Path.join(root, "mix.exs"), """
    defmodule Fixture.MixProject do
      use Mix.Project

      def project do
        [app: :fixture, version: "0.1.0", deps: deps()]
      end

      def application do
        []
      end

      defp deps do
        #{deps}
      end
    end
    """)
  end

  defp tmp_dir(context) do
    name = context.test |> Atom.to_string() |> :erlang.phash2() |> Integer.to_string(36)

    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_locator_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
