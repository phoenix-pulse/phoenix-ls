defmodule PhoenixLS.Introspection.Router.Resource do
  @moduledoc """
  Resource route expansion for Phoenix router source introspection.
  """

  alias PhoenixLS.Introspection.Router.Args
  alias PhoenixLS.Introspection.Router.Path, as: RouterPath

  @resource_actions [:index, :new, :edit, :show, :create, :update, :delete]
  @singleton_resource_actions [:show, :new, :edit, :create, :update, :delete]

  @type options_result ::
          {:ok, [atom()], String.t(), boolean(), [String.t()], term() | nil}
          | :error

  @spec options(String.t(), [term()]) :: options_result()
  def options(path, rest) do
    with {:ok, opts, block} <- resource_args(rest) do
      singleton? = Keyword.get(opts, :singleton, false) == true
      valid_actions = if singleton?, do: @singleton_resource_actions, else: @resource_actions

      {:ok, actions(opts, valid_actions), resource_param(opts), singleton?,
       resource_helper_segments(path, opts), block}
    end
  end

  @spec route_specs(String.t(), atom(), String.t(), boolean()) :: [{atom(), String.t(), atom()}]
  def route_specs(base_path, :index, _param, false), do: [{:get, base_path, :index}]
  def route_specs(_base_path, :index, _param, true), do: []

  def route_specs(base_path, :new, _param, _singleton?),
    do: [{:get, RouterPath.join(base_path, "new"), :new}]

  def route_specs(base_path, :edit, _param, true),
    do: [{:get, RouterPath.join(base_path, "edit"), :edit}]

  def route_specs(base_path, :edit, param, false),
    do: [{:get, RouterPath.join(base_path, ":#{param}/edit"), :edit}]

  def route_specs(base_path, :show, _param, true),
    do: [{:get, base_path, :show}]

  def route_specs(base_path, :show, param, false),
    do: [{:get, RouterPath.join(base_path, ":#{param}"), :show}]

  def route_specs(base_path, :create, _param, _singleton?),
    do: [{:post, base_path, :create}]

  def route_specs(base_path, :update, _param, true) do
    [{:patch, base_path, :update}, {:put, base_path, :update}]
  end

  def route_specs(base_path, :update, param, false) do
    path = RouterPath.join(base_path, ":#{param}")
    [{:patch, path, :update}, {:put, path, :update}]
  end

  def route_specs(base_path, :delete, _param, true),
    do: [{:delete, base_path, :delete}]

  def route_specs(base_path, :delete, param, false),
    do: [{:delete, RouterPath.join(base_path, ":#{param}"), :delete}]

  @spec nested_scope_path(String.t(), [String.t()], String.t(), boolean()) :: String.t()
  def nested_scope_path(base_path, _resource_helper_segments, _param, true),
    do: base_path

  def nested_scope_path(base_path, resource_helper_segments, param, false) do
    RouterPath.join(base_path, ":#{nested_resource_param(resource_helper_segments, param)}")
  end

  defp resource_args([]), do: {:ok, [], nil}

  defp resource_args([[do: block]]), do: {:ok, [], block}

  defp resource_args([opts]) when is_list(opts) do
    if Args.options_arg?(opts) do
      {:ok, opts, nil}
    else
      :error
    end
  end

  defp resource_args([opts, [do: block]]) when is_list(opts) do
    if Args.options_arg?(opts) do
      {:ok, opts, block}
    else
      :error
    end
  end

  defp resource_args(_rest), do: :error

  defp actions(opts, valid_actions) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    requested_actions =
      case only do
        actions when is_list(actions) -> actions
        nil -> valid_actions
        _other -> []
      end

    requested_actions
    |> Enum.filter(&(&1 in valid_actions))
    |> Enum.reject(&(&1 in except_actions(except)))
  end

  defp except_actions(except) when is_list(except), do: except
  defp except_actions(_except), do: []

  defp resource_param(opts) do
    case Keyword.get(opts, :param, "id") do
      param when is_binary(param) -> param
      param when is_atom(param) -> Atom.to_string(param)
      _other -> "id"
    end
  end

  defp resource_helper_segments(path, opts) do
    case Keyword.fetch(opts, :as) do
      {:ok, nil} -> []
      {:ok, false} -> []
      {:ok, helper} -> RouterPath.helper_segments_from_value(helper)
      :error -> RouterPath.helper_segments_from_path(path)
    end
  end

  defp nested_resource_param(resource_helper_segments, param) do
    resource_name =
      resource_helper_segments
      |> List.last()
      |> case do
        nil -> "resource"
        name -> name
      end

    "#{resource_name}_#{param}"
  end
end
