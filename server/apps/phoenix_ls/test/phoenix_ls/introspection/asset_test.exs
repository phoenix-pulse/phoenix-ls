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

  test "builds public paths for umbrella app static asset facts", context do
    root = tmp_dir(context)
    path = Path.join([root, "apps", "shop", "priv", "static", "images", "logo.svg"])
    uri = SupportURI.path_to_file_uri!(path)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "<svg></svg>")

    assert [fact] = Asset.facts(uri, path, root)
    assert fact.id == "/images/logo.svg"
    assert fact.data.public_path == "/images/logo.svg"
    assert fact.data.file_path == path
    assert fact.data.type == :image
  end

  test "extracts LiveView hook facts from supported JavaScript hook maps", context do
    root = tmp_dir(context)
    path = Path.join([root, "priv", "static", "assets", "app.js"])
    uri = SupportURI.path_to_file_uri!(path)

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    let Hooks = {}
    Hooks.PhoneNumber = {
      mounted() {}
    }
    """)

    facts = Asset.facts(uri, path, root, version: 3)

    assert asset_fact = Enum.find(facts, &(&1.kind == :asset))
    assert asset_fact.data.type == :script

    assert hook_fact = Enum.find(facts, &(&1.kind == :hook))
    assert hook_fact.uri == uri
    assert hook_fact.data.name == "PhoneNumber"
    assert hook_fact.data.source == :javascript_hook_map
    assert hook_fact.range.start.line == 1
    assert hook_fact.range.start.character == 6
    assert hook_fact.range.end.character == 17

    assert hook_fact.provenance == %{
             source: :static_asset,
             scanner: :live_view_hook_map,
             document_version: 3
           }
  end

  test "ignores hook map assignments in JavaScript line comments", context do
    root = tmp_dir(context)
    path = Path.join([root, "priv", "static", "assets", "app.js"])
    uri = SupportURI.path_to_file_uri!(path)

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    let Hooks = {}
    // Hooks.Commented = {
    Hooks.Real = {
      mounted() {}
    }
    """)

    hook_facts =
      uri
      |> Asset.facts(path, root)
      |> Enum.filter(&(&1.kind == :hook))

    assert Enum.map(hook_facts, & &1.data.name) == ["Real"]

    assert [real] = hook_facts
    assert real.range.start.line == 2
    assert real.range.start.character == 6
    assert real.range.end.character == 10
  end

  test "ignores hook map assignments in JavaScript block comments", context do
    root = tmp_dir(context)
    path = Path.join([root, "priv", "static", "assets", "app.js"])
    uri = SupportURI.path_to_file_uri!(path)

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    let Hooks = {}
    /*
    Hooks.Commented = {
      mounted() {}
    }
    */
    Hooks.Real = {
      mounted() {}
    }
    """)

    hook_facts =
      uri
      |> Asset.facts(path, root)
      |> Enum.filter(&(&1.kind == :hook))

    assert Enum.map(hook_facts, & &1.data.name) == ["Real"]

    assert [real] = hook_facts
    assert real.range.start.line == 6
    assert real.range.start.character == 6
    assert real.range.end.character == 10
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
