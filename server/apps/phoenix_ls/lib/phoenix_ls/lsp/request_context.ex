defmodule PhoenixLS.LSP.RequestContext do
  @moduledoc """
  Immutable context snapshot for LSP request and notification handlers.
  """

  alias GenLSP.LSP
  alias PhoenixLS.Project.Manager

  @enforce_keys [:lsp, :assigns]
  defstruct [:lsp, :assigns]

  @type t :: %__MODULE__{lsp: LSP.t(), assigns: map()}

  @spec new(LSP.t()) :: t()
  def new(lsp) do
    %__MODULE__{lsp: lsp, assigns: LSP.assigns(lsp)}
  end

  @spec known_project_roots(t()) :: [String.t()]
  def known_project_roots(%__MODULE__{assigns: assigns}) do
    workspace_roots =
      assigns
      |> Map.get(:workspace_project_roots, MapSet.new())
      |> MapSet.to_list()

    case Map.get(assigns, :project_root_uri) do
      nil -> workspace_roots
      root_uri -> [root_uri | workspace_roots]
    end
    |> Enum.uniq()
    |> Enum.sort_by(&String.length/1, :desc)
  end

  @spec project_engine_for_uri(t(), String.t()) :: {:ok, PhoenixLS.Project.Engine.t()} | :error
  def project_engine_for_uri(%__MODULE__{} = context, uri) when is_binary(uri) do
    with project_manager when not is_nil(project_manager) <-
           Map.get(context.assigns, :project_manager),
         root_uri when is_binary(root_uri) <- matching_project_root(context, uri) do
      case Manager.fetch_engine(project_manager, root_uri) do
        {:ok, engine} -> {:ok, engine}
        :error -> :error
      end
    else
      _missing -> :error
    end
  end

  @spec matching_project_root(t(), String.t()) :: String.t() | nil
  def matching_project_root(%__MODULE__{} = context, uri) when is_binary(uri) do
    context
    |> known_project_roots()
    |> Enum.find(&uri_within_root?(uri, &1))
  end

  @spec refresh(t()) :: t()
  def refresh(%__MODULE__{lsp: lsp}), do: new(lsp)

  defp uri_within_root?(uri, root_uri) do
    uri == root_uri or String.starts_with?(uri, root_uri <> "/")
  end
end
