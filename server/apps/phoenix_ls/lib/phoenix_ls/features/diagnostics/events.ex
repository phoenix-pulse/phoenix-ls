defmodule PhoenixLS.Features.Diagnostics.Events do
  @moduledoc """
  Diagnostics for LiveView event handler references in HEEx.
  """

  alias PhoenixLS.Features.Diagnostics.Builder
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.LiveView.Attributes

  @spec diagnostics(Tag.t(), MapSet.t(), [String.t()]) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(%Tag{} = tag, events, event_names) do
    tag.attrs
    |> Enum.filter(&event_attr?/1)
    |> Enum.filter(&literal_attr_value?/1)
    |> Enum.reject(&blank?(&1.value))
    |> Enum.reject(&MapSet.member?(events, &1.value))
    |> Enum.map(&unknown_event_diagnostic(&1, event_names))
  end

  defp unknown_event_diagnostic(%Attribute{} = attr, event_names) do
    Builder.diagnostic(
      attr.value_range || attr.name_range,
      "phoenix.unknown_event",
      ~s(Missing handle_event/3 handler for LiveView event "#{attr.value}"),
      %{
        "kind" => "missing_live_event_handler",
        "event" => attr.value,
        "attribute" => attr.name,
        "handler" => "handle_event/3",
        "knownEvents" => event_names
      }
    )
  end

  defp event_attr?(%Attribute{name: name}), do: Attributes.event_attr?(name)

  defp literal_attr_value?(%Attribute{value_kind: kind}) when kind in [:quoted, :unquoted],
    do: true

  defp literal_attr_value?(_attr), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
