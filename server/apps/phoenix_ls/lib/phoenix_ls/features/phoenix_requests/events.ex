defmodule PhoenixLS.Features.PhoenixRequests.Events do
  @moduledoc """
  Payload builder for LiveView event explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.Payload
  alias PhoenixLS.Index.Fact

  @spec list(term()) :: [map()]
  def list(facts) do
    handlers = Payload.facts_by_kind(facts, :live_event)
    handler_index = event_handler_index(handlers)

    (Enum.map(handlers, &live_event_payload/1) ++
       (facts
        |> Payload.facts_by_kind(:live_event_usage)
        |> Enum.map(&event_usage_payload(&1, handler_index))))
    |> Enum.sort_by(&{&1["module"], &1["name"], event_source_rank(&1), &1["filePath"]})
  end

  @spec function_payload(Fact.t()) :: map()
  def function_payload(fact) do
    %{
      "name" => "handle_event",
      "type" => event_type(fact),
      "eventName" => fact.data.event,
      "handler" => Map.get(fact.data, :handler) || event_type(fact),
      "arity" => Map.get(fact.data, :arity),
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    }
  end

  defp live_event_payload(fact) do
    %{
      "name" => fact.data.event,
      "type" => event_type(fact),
      "handler" => Map.get(fact.data, :handler) || event_type(fact),
      "arity" => Map.get(fact.data, :arity),
      "module" => fact.data.module,
      "source" => "handler",
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    }
  end

  defp event_usage_payload(fact, handler_index) do
    handler_fact = Map.get(handler_index, {fact.data.module, fact.data.event})

    %{
      "name" => fact.data.event,
      "type" => fact.data.attribute,
      "handler" => fact.data.handler,
      "arity" => fact.data.arity,
      "module" => fact.data.module,
      "source" => "usage",
      "handled" => not is_nil(handler_fact),
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact),
      "attribute" => fact.data.attribute
    }
    |> Payload.maybe_put("handlerFilePath", handler_file_path(handler_fact))
    |> Payload.maybe_put("handlerLocation", handler_location(handler_fact))
  end

  defp event_handler_index(handlers) do
    Map.new(handlers, &{{&1.data.module, &1.data.event}, &1})
  end

  defp handler_file_path(%Fact{} = fact), do: Payload.file_path(fact.uri)
  defp handler_file_path(_fact), do: nil

  defp handler_location(%Fact{} = fact), do: Payload.location(fact)
  defp handler_location(_fact), do: nil

  defp event_source_rank(%{"source" => "handler"}), do: 0
  defp event_source_rank(%{"source" => "usage"}), do: 1
  defp event_source_rank(_payload), do: 2

  defp event_type(%Fact{data: %{type: type}}) when is_atom(type), do: Atom.to_string(type)
  defp event_type(%Fact{data: %{type: type}}) when is_binary(type), do: type
  defp event_type(_fact), do: "handle_event"
end
