defmodule PhoenixLS.Features.PhoenixRequests.Payload do
  @moduledoc """
  Shared payload helpers for Phoenix editor explorer requests.
  """

  alias PhoenixLS.Index.{Fact, Snapshot}
  alias PhoenixLS.Support.URI, as: SupportURI

  @spec facts_by_kind(Snapshot.t(), atom()) :: [Fact.t()]
  def facts_by_kind(%Snapshot{} = snapshot, kind) do
    Snapshot.by_kind(snapshot, kind)
  end

  @spec location(Fact.t()) :: map()
  def location(%Fact{range: %{start: start}}) do
    %{
      "line" => start.line,
      "character" => start.character
    }
  end

  @spec file_path(String.t()) :: String.t()
  def file_path(uri) do
    case SupportURI.file_uri_to_path(uri) do
      {:ok, path} -> path
      {:error, _reason} -> uri
    end
  end

  @spec option_payload(keyword() | nil) :: map()
  def option_payload(options) do
    options = options || []

    %{}
    |> maybe_put("default", option_value(options, :default, &inspect/1))
    |> maybe_put("values", option_value(options, :values, &values/1))
    |> maybe_put("doc", Keyword.get(options, :doc))
  end

  @spec association_option_payload(keyword() | nil) :: map()
  def association_option_payload(options) do
    options = options || []

    %{}
    |> maybe_put("joinThrough", option_value(options, :join_through, &option_string/1))
    |> maybe_put("joinKeys", option_value(options, :join_keys, &inspect/1))
    |> maybe_put("onReplace", option_value(options, :on_replace, &value_string/1))
    |> maybe_put("defineField", option_value(options, :define_field, & &1))
  end

  @spec maybe_put(map(), String.t(), term()) :: map()
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec type_string(term()) :: String.t()
  def type_string(type) when is_atom(type), do: Atom.to_string(type)
  def type_string(type), do: inspect(type)

  @spec optional_atom_string(term()) :: String.t() | nil
  def optional_atom_string(nil), do: nil
  def optional_atom_string(value) when is_atom(value), do: Atom.to_string(value)
  def optional_atom_string(value) when is_binary(value), do: value

  @spec confidence_string(term()) :: String.t() | nil
  def confidence_string(nil), do: nil
  def confidence_string(value) when is_atom(value), do: Atom.to_string(value)
  def confidence_string(value) when is_binary(value), do: value

  @spec format_string(term()) :: String.t()
  def format_string(format) when is_atom(format), do: Atom.to_string(format)
  def format_string(format), do: to_string(format)

  @spec required?(keyword() | nil) :: boolean()
  def required?(options), do: Keyword.get(options || [], :required, false) == true

  @spec route_payload(Fact.t()) :: map()
  def route_payload(%Fact{} = fact) do
    action = optional_atom_string(Map.get(fact.data, :action))
    pipelines = Map.get(fact.data, :pipelines, [])

    %{
      "verb" => Atom.to_string(fact.data.verb),
      "path" => fact.data.path,
      "controller" => fact.data.plug,
      "action" => action || "",
      "filePath" => file_path(fact.uri),
      "location" => location(fact),
      "helperBase" => fact.data.helper_base,
      "helperName" => helper_name(fact.data.helper_base),
      "helperPrefix" => Map.get(fact.data, :helper_prefix),
      "helperVariants" => ["path", "url"],
      "pathParams" => fact.data.path_params,
      "scopePath" => fact.data.scope_path || "/",
      "pipeline" => Enum.join(pipelines, ", "),
      "pipelines" => pipelines,
      "liveSession" => Map.get(fact.data, :live_session),
      "liveModule" => live_module(fact),
      "liveAction" => live_action(fact)
    }
  end

  defp option_value(options, key, transform) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> transform.(value)
      :error -> nil
    end
  end

  defp values(values) when is_list(values), do: Enum.map(values, &value_string/1)
  defp values(value), do: [value_string(value)]

  defp value_string(value) when is_atom(value), do: Atom.to_string(value)
  defp value_string(value), do: inspect(value)

  defp option_string(value) when is_binary(value), do: value
  defp option_string(value), do: inspect(value)

  defp live_module(%Fact{data: %{verb: :live, plug: plug}}), do: plug
  defp live_module(_fact), do: nil

  defp live_action(%Fact{data: %{verb: :live, action: action}}) do
    optional_atom_string(action)
  end

  defp live_action(_fact), do: nil

  defp helper_name(helper_base) when is_binary(helper_base) and helper_base != "" do
    helper_base <> "_path"
  end

  defp helper_name(_helper_base), do: nil
end
