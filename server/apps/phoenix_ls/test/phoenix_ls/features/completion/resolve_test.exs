defmodule PhoenixLS.Features.Completion.ResolveTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.CompletionItem
  alias PhoenixLS.Features.Completion.Resolve

  test "adds documentation for route helper completion payloads" do
    item = %CompletionItem{
      label: "user_path",
      detail: "Routes.user_path",
      data: %{"kind" => "route_helper", "helper" => "user_path"}
    }

    assert %{documentation: documentation} = Resolve.resolve(item)
    assert documentation =~ "Routes.user_path"
    assert documentation =~ "router"
  end
end
