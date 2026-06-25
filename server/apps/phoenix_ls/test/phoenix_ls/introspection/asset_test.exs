defmodule PhoenixLS.Introspection.AssetTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Introspection.Asset
  alias PhoenixLS.Support.URI, as: SupportURI

  test "builds source-located static asset facts", context do
    root = tmp_dir(context)
    path = Path.join([root, "priv", "static", "images", "logo.svg"])
    uri = SupportURI.path_to_file_uri!(path)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "<svg></svg>")

    assert [fact] = Asset.facts(uri, path, root)
    assert fact.kind == :asset
    assert fact.id == "/images/logo.svg"
    assert fact.uri == uri
    assert fact.range.start.line == 0
    assert fact.range.end.line == 0
    assert fact.provenance == %{source: :static_asset}
    assert fact.data.public_path == "/images/logo.svg"
    assert fact.data.file_path == path
    assert fact.data.type == :image
    assert fact.data.size == 11
  end

  test "ignores non-static and unsupported files", context do
    root = tmp_dir(context)
    outside_path = Path.join([root, "assets", "app.css"])
    manifest_path = Path.join([root, "priv", "static", "cache_manifest.json"])

    File.mkdir_p!(Path.dirname(outside_path))
    File.write!(outside_path, "body {}")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, "{}")

    assert Asset.facts(SupportURI.path_to_file_uri!(outside_path), outside_path, root) == []
    assert Asset.facts(SupportURI.path_to_file_uri!(manifest_path), manifest_path, root) == []
  end

  defp tmp_dir(context) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_ls_asset_#{context.test |> Atom.to_string() |> :erlang.phash2()}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    path
  end
end
