defmodule PhoenixLS.LSP.Mode do
  @moduledoc """
  Normalizes Phoenix LS runtime mode from editor intent and detected peers.
  """

  @type mode :: :auto | :companion | :full
  @type resolved_mode :: :companion | :full

  @spec parse(term()) :: mode()
  def parse(value) when value in [:auto, :companion, :full], do: value

  def parse(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "auto" -> :auto
      "companion" -> :companion
      "full" -> :full
      _unknown -> :auto
    end
  end

  def parse(_value), do: :auto

  @spec resolve(mode(), boolean()) :: resolved_mode()
  def resolve(:auto, true), do: :companion
  def resolve(:auto, false), do: :full
  def resolve(:companion, _detected_expert?), do: :companion
  def resolve(:full, _detected_expert?), do: :full
end
