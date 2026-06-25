defmodule PhoenixLS.Project.Metadata do
  @moduledoc """
  Engine-owned source-only Mix project metadata.
  """

  use GenServer

  alias PhoenixLS.Support.URI, as: SupportURI

  @phoenix_dependencies MapSet.new([:phoenix, :phoenix_live_view])

  @enforce_keys [:root_uri]
  defstruct [
    :root_uri,
    :root_path,
    :mix_exs_path,
    phoenix?: false
  ]

  @type t :: %__MODULE__{
          root_uri: String.t(),
          root_path: String.t() | nil,
          mix_exs_path: String.t() | nil,
          phoenix?: boolean()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec fetch(GenServer.server()) :: t()
  def fetch(server), do: GenServer.call(server, :fetch)

  @impl true
  def init(opts) do
    root_uri = Keyword.fetch!(opts, :root_uri)

    {:ok, read(root_uri)}
  end

  @impl true
  def handle_call(:fetch, _from, metadata) do
    {:reply, metadata, metadata}
  end

  defp read(root_uri) do
    case SupportURI.file_uri_to_path(root_uri) do
      {:ok, root_path} ->
        mix_exs_path = Path.join(root_path, "mix.exs")

        %__MODULE__{
          root_uri: root_uri,
          root_path: root_path,
          mix_exs_path: mix_exs_path,
          phoenix?: phoenix_dependency?(mix_exs_path)
        }

      {:error, _reason} ->
        %__MODULE__{root_uri: root_uri}
    end
  end

  defp phoenix_dependency?(mix_exs_path) do
    with {:ok, source} <- File.read(mix_exs_path),
         {:ok, quoted} <- Code.string_to_quoted(source) do
      {_quoted, found?} = Macro.prewalk(quoted, false, &detect_phoenix_dependency/2)

      found?
    else
      _error -> false
    end
  end

  defp detect_phoenix_dependency(node, true), do: {node, true}

  defp detect_phoenix_dependency({dependency, requirement} = node, false)
       when is_atom(dependency) and is_binary(requirement) do
    {node, MapSet.member?(@phoenix_dependencies, dependency)}
  end

  defp detect_phoenix_dependency({dependency, requirement, opts} = node, false)
       when is_atom(dependency) and is_binary(requirement) and is_list(opts) do
    {node, MapSet.member?(@phoenix_dependencies, dependency)}
  end

  defp detect_phoenix_dependency({:{}, _meta, [dependency | _rest]} = node, false)
       when is_atom(dependency) do
    {node, MapSet.member?(@phoenix_dependencies, dependency)}
  end

  defp detect_phoenix_dependency(node, false), do: {node, false}
end
