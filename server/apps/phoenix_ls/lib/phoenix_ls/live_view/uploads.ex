defmodule PhoenixLS.LiveView.Uploads do
  @moduledoc """
  Shared LiveView upload metadata and literal value helpers.
  """

  defmodule Upload do
    @moduledoc """
    Typed LiveView upload fact payload.
    """

    @enforce_keys [:module, :name]
    defstruct [:module, :name, options: []]
  end

  @option_names [
    :accept,
    :auto_upload,
    :chunk_size,
    :chunk_timeout,
    :external,
    :max_entries,
    :max_file_size,
    :progress,
    :writer
  ]

  @spec option_names() :: [atom()]
  def option_names, do: @option_names

  @spec option_name?(term()) :: boolean()
  def option_name?(name) when is_atom(name), do: name in @option_names
  def option_name?(_name), do: false

  @spec static_name(term()) :: {:ok, String.t()} | :error
  def static_name(name) when is_atom(name) and not is_boolean(name) and not is_nil(name),
    do: {:ok, Atom.to_string(name)}

  def static_name(name) when is_binary(name), do: {:ok, name}
  def static_name(_name), do: :error
end
