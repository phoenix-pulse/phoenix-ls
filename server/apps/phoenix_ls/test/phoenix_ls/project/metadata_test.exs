defmodule PhoenixLS.Project.MetadataTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Project.Metadata
  alias PhoenixLS.Support.URI, as: SupportURI

  test "reads Phoenix dependency metadata from mix.exs without executing project code", context do
    root =
      fixture_project(context, "phoenix_project", """
      raise "project code was executed"

      defmodule Fixture.MixProject do
        use Mix.Project

        def project do
          [app: :fixture, version: "0.1.0", deps: deps()]
        end

        defp deps do
          [{:phoenix, "~> 1.7"}]
        end
      end
      """)

    metadata = start_supervised!({Metadata, root_uri: SupportURI.path_to_file_uri!(root)})

    assert %Metadata{
             root_path: ^root,
             mix_exs_path: mix_exs_path,
             phoenix?: true
           } = Metadata.fetch(metadata)

    assert mix_exs_path == Path.join(root, "mix.exs")
  end

  test "reports non-Phoenix projects without reading dependencies in the manager", context do
    root =
      fixture_project(context, "plain_project", """
      defmodule Fixture.MixProject do
        use Mix.Project

        def project do
          [app: :fixture, version: "0.1.0", deps: []]
        end
      end
      """)

    metadata = start_supervised!({Metadata, root_uri: SupportURI.path_to_file_uri!(root)})

    assert %Metadata{phoenix?: false} = Metadata.fetch(metadata)
  end

  defp fixture_project(context, name, mix_source) do
    root = Path.join(tmp_dir(context), name)
    File.mkdir_p!(root)
    File.write!(Path.join(root, "mix.exs"), mix_source)
    root
  end

  defp tmp_dir(context) do
    name = context.test |> Atom.to_string() |> :erlang.phash2() |> Integer.to_string(36)

    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_metadata_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
