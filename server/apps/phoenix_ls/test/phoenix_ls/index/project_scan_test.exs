defmodule PhoenixLS.Index.ProjectScanTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Index.ProjectScan
  alias PhoenixLS.Support.URI, as: SupportURI

  test "returns sorted source file uris under lib", context do
    root = tmp_dir(context)

    write!(
      Path.join(root, "lib/app_web/live/page_live.ex"),
      "defmodule AppWeb.PageLive do\nend\n"
    )

    write!(
      Path.join(root, "lib/app_web/components/core_components.ex"),
      "defmodule AppWeb.CoreComponents do\nend\n"
    )

    write!(Path.join(root, "lib/app_web/controllers/page_html/index.html.heex"), "<section />")
    write!(Path.join(root, "priv/static/images/logo.svg"), "<svg></svg>")
    write!(Path.join(root, "priv/static/assets/app.css"), "body {}")
    write!(Path.join(root, "priv/static/cache_manifest.json"), "{}")
    write!(Path.join(root, "lib/app_web/controllers/page_html/README.md"), "# ignored\n")
    write!(Path.join(root, "test/support/fixture.ex"), "defmodule TestSupport do\nend\n")
    write!(Path.join(root, "deps/example/lib/dependency.ex"), "defmodule Dependency do\nend\n")
    write!(Path.join(root, "_build/dev/lib/generated.ex"), "defmodule Generated do\nend\n")

    assert ProjectScan.uris(SupportURI.path_to_file_uri!(root)) ==
             {:ok,
              [
                SupportURI.path_to_file_uri!(
                  Path.join(root, "lib/app_web/components/core_components.ex")
                ),
                SupportURI.path_to_file_uri!(
                  Path.join(root, "lib/app_web/controllers/page_html/index.html.heex")
                ),
                SupportURI.path_to_file_uri!(Path.join(root, "lib/app_web/live/page_live.ex")),
                SupportURI.path_to_file_uri!(Path.join(root, "priv/static/assets/app.css")),
                SupportURI.path_to_file_uri!(Path.join(root, "priv/static/images/logo.svg"))
              ]}
  end

  test "rejects non-file root uris" do
    assert ProjectScan.uris("untitled:Project") == {:error, :not_file_uri}
  end

  defp write!(path, text) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text)
  end

  defp tmp_dir(context) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_project_scan_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
