defmodule PhoenixLS.Introspection.Router.Args do
  @moduledoc """
  Shared AST argument predicates for router macro parsing.
  """

  @spec options_arg?(term()) :: boolean()
  def options_arg?(opts) when is_list(opts) do
    not block_arg?(opts) and
      Enum.all?(opts, fn
        {key, _value} when is_atom(key) -> true
        _other -> false
      end)
  end

  def options_arg?(_opts), do: false

  @spec block_arg?(term()) :: boolean()
  def block_arg?([{:do, _block}]), do: true
  def block_arg?(_opts), do: false
end
