defmodule PhoenixLS.LiveView.Navigation do
  @moduledoc """
  Shared LiveView navigation route classification.
  """

  alias PhoenixLS.HEEx.Document.Attribute
  alias PhoenixLS.Index.Fact

  defmodule Reference do
    @moduledoc """
    Typed source navigation reference fact payload.
    """

    @enforce_keys [:module, :navigation, :path]
    defstruct [:module, :navigation, :path]
  end

  @type navigation :: :patch | :navigate
  @type current_context :: %{
          required(:module) => String.t(),
          optional(:action) => atom() | String.t()
        }

  @spec classify(navigation(), String.t() | current_context(), String.t(), [Fact.t()]) ::
          :ok
          | :unknown
          | {:invalid_live_patch, Fact.t()}
          | {:invalid_live_patch_route, Fact.t()}
          | {:invalid_live_navigate, Fact.t(), Fact.t()}
          | {:invalid_live_navigate_route, Fact.t()}
          | {:missing_handle_params, Fact.t()}
  def classify(navigation, current_module, path, facts)
      when navigation in [:patch, :navigate] and is_binary(current_module) and is_binary(path) and
             is_list(facts) do
    classify(navigation, %{module: current_module}, path, facts)
  end

  def classify(navigation, %{module: current_module} = current_context, path, facts)
      when navigation in [:patch, :navigate] and is_binary(current_module) and is_binary(path) and
             is_list(facts) do
    case navigation do
      :patch -> classify_patch(current_module, path, facts)
      :navigate -> classify_navigate(current_context, path, facts)
    end
  end

  @spec route_path_match?(String.t(), String.t()) :: boolean()
  def route_path_match?(route_path, path) when is_binary(route_path) and is_binary(path) do
    match_route_segments(path_segments(route_path), path_segments(path))
  end

  @spec verified_route_path(Attribute.t()) :: {:ok, String.t()} | :error
  def verified_route_path(%Attribute{value: value}) when is_binary(value) do
    cond do
      String.starts_with?(value, "~p\"") and String.ends_with?(value, "\"") ->
        {:ok, value |> String.trim_leading("~p\"") |> String.trim_trailing("\"")}

      String.starts_with?(value, "~p'") and String.ends_with?(value, "'") ->
        {:ok, value |> String.trim_leading("~p'") |> String.trim_trailing("'")}

      true ->
        :error
    end
  end

  def verified_route_path(_attr), do: :error

  defp classify_patch(current_module, path, facts) do
    case target_route(facts, path) do
      %Fact{} = target ->
        if live_route?(target) do
          cond do
            target.data.plug != current_module ->
              {:invalid_live_patch, target}

            handle_params?(facts, current_module) ->
              :ok

            true ->
              {:missing_handle_params, target}
          end
        else
          {:invalid_live_patch_route, target}
        end

      nil ->
        :unknown
    end
  end

  defp classify_navigate(current_context, path, facts) do
    case target_route(facts, path) do
      %Fact{} = target ->
        if live_route?(target) do
          case current_live_routes(facts, current_context) do
            [_current | _rest] = current_routes ->
              classify_navigate_session(current_routes, target)

            [] ->
              :unknown
          end
        else
          {:invalid_live_navigate_route, target}
        end

      nil ->
        :unknown
    end
  end

  defp classify_navigate_session(current_routes, %Fact{} = target) do
    case Enum.reject(current_routes, &same_live_session?(&1, target)) do
      [] ->
        :ok

      [different_session_route | _rest] ->
        {:invalid_live_navigate, different_session_route, target}
    end
  end

  defp target_route(facts, path) do
    facts
    |> routes()
    |> Enum.find(&route_path_match?(&1.data.path, path))
  end

  defp current_live_routes(facts, %{module: module, action: action}) when is_atom(action) do
    facts
    |> live_routes()
    |> Enum.filter(&(&1.data.plug == module and route_action_match?(&1, action)))
    |> Enum.sort_by(& &1.data.path)
  end

  defp current_live_routes(facts, %{module: module, action: action}) when is_binary(action) do
    facts
    |> live_routes()
    |> Enum.filter(&(&1.data.plug == module and route_action_match?(&1, action)))
    |> Enum.sort_by(& &1.data.path)
  end

  defp current_live_routes(facts, %{module: module}) do
    facts
    |> live_routes()
    |> Enum.filter(&(&1.data.plug == module))
    |> Enum.sort_by(& &1.data.path)
  end

  defp live_routes(facts) do
    Enum.filter(routes(facts), &live_route?/1)
  end

  defp routes(facts) do
    Enum.filter(facts, &(&1.kind == :route))
  end

  defp live_route?(%Fact{data: %{verb: :live}}), do: true
  defp live_route?(_fact), do: false

  defp route_verb(%Fact{data: %{verb: verb}}), do: verb

  @spec route_verb_name(Fact.t()) :: String.t()
  def route_verb_name(%Fact{} = fact) do
    fact
    |> route_verb()
    |> Atom.to_string()
  end

  defp same_live_session?(%Fact{} = left, %Fact{} = right) do
    left.data.live_session == right.data.live_session
  end

  defp route_action_match?(%Fact{data: %{action: action}}, action), do: true

  defp route_action_match?(%Fact{data: %{action: action}}, expected) when is_atom(action) do
    Atom.to_string(action) == expected
  end

  defp route_action_match?(_fact, _expected), do: false

  defp handle_params?(facts, module) do
    Enum.any?(facts, fn
      %Fact{
        kind: :live_view_function,
        data: %{module: ^module, name: "handle_params", type: :handle_params, arity: 3}
      } ->
        true

      _fact ->
        false
    end)
  end

  defp match_route_segments([], []), do: true
  defp match_route_segments(["*" <> _name], _segments), do: true

  defp match_route_segments([":" <> _name | route_rest], [_segment | path_rest]) do
    match_route_segments(route_rest, path_rest)
  end

  defp match_route_segments([segment | route_rest], [segment | path_rest]) do
    match_route_segments(route_rest, path_rest)
  end

  defp match_route_segments(_route_segments, _path_segments), do: false

  defp path_segments(path) do
    String.split(path, "/", trim: true)
  end
end
