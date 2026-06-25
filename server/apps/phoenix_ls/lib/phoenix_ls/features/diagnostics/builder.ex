defmodule PhoenixLS.Features.Diagnostics.Builder do
  @moduledoc """
  Builds PhoenixLS diagnostics with a consistent source.
  """

  alias GenLSP.Enumerations.DiagnosticSeverity
  alias GenLSP.Structures.Diagnostic

  @source "PhoenixLS"

  @spec source() :: String.t()
  def source, do: @source

  @spec diagnostic(term(), String.t(), String.t(), map() | nil, integer()) :: Diagnostic.t()
  def diagnostic(range, code, message, data \\ nil, severity \\ DiagnosticSeverity.error()) do
    %Diagnostic{
      range: range,
      severity: severity,
      code: code,
      source: @source,
      message: message,
      data: data
    }
  end
end
