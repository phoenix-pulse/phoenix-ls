defmodule PhoenixLS.Features.PhoenixRequests.LiveViews do
  @moduledoc """
  Payload builder for LiveView explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.{Events, Payload}

  @spec list(term()) :: [map()]
  def list(facts) do
    events_by_module =
      facts
      |> Payload.facts_by_kind(:live_event)
      |> Enum.group_by(& &1.data.module)

    functions_by_module =
      facts
      |> Payload.facts_by_kind(:live_view_function)
      |> Enum.group_by(& &1.data.module)

    assigns_by_module =
      facts
      |> Payload.facts_by_kind(:assign)
      |> Enum.group_by(& &1.data.module)

    async_by_module =
      facts
      |> Payload.facts_by_kind(:live_async)
      |> Enum.group_by(& &1.data.module)

    temporary_assigns_by_module =
      facts
      |> Payload.facts_by_kind(:live_temporary_assign)
      |> Enum.group_by(& &1.data.module)

    hooks_by_module =
      facts
      |> Payload.facts_by_kind(:live_lifecycle_hook)
      |> Enum.group_by(& &1.data.module)

    messages_by_module =
      facts
      |> Payload.facts_by_kind(:live_message)
      |> Enum.group_by(& &1.data.module)

    facts
    |> Payload.facts_by_kind(:live_view)
    |> Enum.map(fn fact ->
      events = Map.get(events_by_module, fact.data.module, [])
      functions = Map.get(functions_by_module, fact.data.module, [])
      assigns = Map.get(assigns_by_module, fact.data.module, [])
      async = Map.get(async_by_module, fact.data.module, [])
      temporary_assigns = Map.get(temporary_assigns_by_module, fact.data.module, [])
      hooks = Map.get(hooks_by_module, fact.data.module, [])
      messages = Map.get(messages_by_module, fact.data.module, [])

      %{
        "module" => fact.data.module,
        "filePath" => Payload.file_path(fact.uri),
        "location" => Payload.location(fact),
        "assigns" => live_view_assign_payloads(assigns),
        "functions" => live_view_function_payloads(functions, events),
        "async" => live_view_async_payloads(async),
        "temporaryAssigns" => live_view_temporary_assign_payloads(temporary_assigns),
        "hooks" => live_view_hook_payloads(hooks),
        "messages" => live_view_message_payloads(messages)
      }
    end)
    |> Enum.sort_by(& &1["module"])
  end

  defp live_view_function_payloads(functions, events) do
    (Enum.map(functions, &live_view_function_payload/1) ++
       Enum.map(events, &Events.function_payload/1))
    |> Enum.sort_by(&live_view_function_sort_key/1)
  end

  defp live_view_assign_payloads(assigns) do
    assigns
    |> Enum.map(&live_view_assign_payload/1)
    |> Enum.sort_by(&live_view_assign_sort_key/1)
  end

  defp live_view_assign_payload(fact) do
    %{
      "name" => fact.data.name,
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    }
  end

  defp live_view_assign_sort_key(payload) do
    location = payload["location"] || %{}
    {location["line"] || 0, location["character"] || 0, payload["name"] || ""}
  end

  defp live_view_async_payloads(async) do
    async
    |> Enum.map(&live_view_async_payload/1)
    |> Enum.sort_by(&live_view_async_sort_key/1)
  end

  defp live_view_async_payload(fact) do
    %{
      "name" => fact.data.name,
      "source" => Atom.to_string(fact.data.source),
      "handler" => fact.data.handler,
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    }
  end

  defp live_view_async_sort_key(payload) do
    location = payload["location"] || %{}

    {
      payload["name"] || "",
      live_view_async_source_rank(payload["source"]),
      location["line"] || 0,
      location["character"] || 0
    }
  end

  defp live_view_async_source_rank("start_async"), do: 0
  defp live_view_async_source_rank("assign_async"), do: 1
  defp live_view_async_source_rank("handle_async"), do: 2
  defp live_view_async_source_rank(_source), do: 3

  defp live_view_temporary_assign_payloads(temporary_assigns) do
    temporary_assigns
    |> Enum.map(&live_view_temporary_assign_payload/1)
    |> Enum.sort_by(&live_view_assign_sort_key/1)
  end

  defp live_view_temporary_assign_payload(fact) do
    %{
      "name" => fact.data.name,
      "default" => fact.data.default,
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    }
  end

  defp live_view_hook_payloads(hooks) do
    hooks
    |> Enum.map(&live_view_hook_payload/1)
    |> Enum.sort_by(&live_view_assign_sort_key/1)
  end

  defp live_view_hook_payload(fact) do
    %{
      "name" => fact.data.name,
      "stage" => Atom.to_string(fact.data.stage),
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    }
  end

  defp live_view_message_payloads(messages) do
    messages
    |> Enum.map(&live_view_message_payload/1)
    |> Enum.sort_by(&live_view_assign_sort_key/1)
  end

  defp live_view_message_payload(fact) do
    %{
      "name" => fact.data.name,
      "pattern" => fact.data.pattern,
      "handler" => fact.data.handler,
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    }
  end

  defp live_view_function_payload(fact) do
    %{
      "name" => fact.data.name,
      "type" => Atom.to_string(fact.data.type),
      "filePath" => Payload.file_path(fact.uri),
      "location" => Payload.location(fact)
    }
  end

  defp live_view_function_sort_key(payload) do
    location = payload["location"] || %{}
    {live_view_function_rank(payload["type"]), location["line"] || 0, location["character"] || 0}
  end

  defp live_view_function_rank("mount"), do: 0
  defp live_view_function_rank("handle_params"), do: 1
  defp live_view_function_rank("handle_async"), do: 2
  defp live_view_function_rank("handle_call"), do: 3
  defp live_view_function_rank("handle_cast"), do: 4
  defp live_view_function_rank("render"), do: 5
  defp live_view_function_rank("handle_event"), do: 6
  defp live_view_function_rank("handle_info"), do: 7
  defp live_view_function_rank(_type), do: 8
end
