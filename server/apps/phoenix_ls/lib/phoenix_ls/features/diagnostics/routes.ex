defmodule PhoenixLS.Features.Diagnostics.Routes do
  @moduledoc """
  Diagnostics for verified route references in HEEx attributes.
  """

  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.LiveView.Navigation

  @spec diagnostics(Tag.t(), MapSet.t()) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(%Tag{} = tag, route_paths) do
    tag.attrs
    |> Enum.flat_map(fn attr ->
      case verified_route_path(attr) do
        {:ok, path} ->
          if known_route_path?(route_paths, path) or static_asset_path?(path) do
            []
          else
            [
              Builder.diagnostic(
                attr.value_range || attr.name_range,
                "phoenix.unknown_route",
                ~s(Unknown verified route "#{path}")
              )
            ]
          end

        :error ->
          []
      end
    end)
  end

  defp known_route_path?(route_paths, path) do
    Enum.any?(route_paths, &route_path_match?(&1, path))
  end

  defp route_path_match?(route_path, path) do
    Navigation.route_path_match?(route_path, path)
  end

  defp static_asset_path?(path) do
    case String.split(path, "/", trim: true) do
      [first | _rest] when first in ["assets", "fonts", "images"] ->
        true

      [filename] ->
        Path.extname(filename) != ""

      _segments ->
        false
    end
  end

  defp verified_route_path(%Attribute{} = attr), do: Navigation.verified_route_path(attr)
end
