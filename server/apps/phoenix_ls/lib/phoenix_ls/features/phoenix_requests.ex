defmodule PhoenixLS.Features.PhoenixRequests do
  @moduledoc """
  Payload builders for Phoenix editor explorer requests.
  """

  alias PhoenixLS.Index.{Fact, Snapshot}
  alias PhoenixLS.Support.URI, as: SupportURI

  @type method :: String.t()

  @spec handle(method(), Snapshot.t()) :: list(map()) | nil
  def handle("phoenix/listSchemas", snapshot), do: list_schemas(snapshot)
  def handle("phoenix/listComponents", snapshot), do: list_components(snapshot)
  def handle("phoenix/listRoutes", snapshot), do: list_routes(snapshot)
  def handle("phoenix/listTemplates", snapshot), do: list_templates(snapshot)
  def handle("phoenix/listEvents", snapshot), do: list_events(snapshot)
  def handle("phoenix/listLiveView", snapshot), do: list_live_view(snapshot)
  def handle("phoenix/" <> _unknown, _snapshot), do: nil

  defp list_schemas(facts) do
    fields_by_schema =
      facts
      |> facts_by_kind(:schema_field)
      |> Enum.group_by(& &1.data.schema)

    associations_by_schema =
      facts
      |> facts_by_kind(:schema_association)
      |> Enum.group_by(& &1.data.schema)

    facts
    |> facts_by_kind(:schema)
    |> Enum.map(fn fact ->
      associations = Map.get(associations_by_schema, fact.id, [])
      fields = Map.get(fields_by_schema, fact.id, [])
      field_payloads = schema_field_payloads(fact, fields, associations)

      %{
        "id" => fact.id,
        "name" => fact.data.module,
        "module" => fact.data.module,
        "source" => fact.data.source,
        "table" => fact.data.source,
        "tableName" => fact.data.source,
        "filePath" => file_path(fact.uri),
        "location" => location(fact),
        "fieldsCount" => length(field_payloads),
        "associationsCount" => length(associations),
        "fields" => field_payloads,
        "associations" => Enum.map(associations, &schema_association_payload/1)
      }
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp list_components(facts) do
    attrs_by_component =
      facts
      |> facts_by_kind(:component_attr)
      |> Enum.group_by(& &1.data.component)

    slots_by_component =
      facts
      |> facts_by_kind(:component_slot)
      |> Enum.group_by(& &1.data.component)

    slot_attrs_by_component =
      facts
      |> facts_by_kind(:component_slot_attr)
      |> Enum.group_by(& &1.data.component)

    facts
    |> facts_by_kind(:component)
    |> Enum.map(fn fact ->
      attrs = Map.get(attrs_by_component, fact.id, [])
      slots = Map.get(slots_by_component, fact.id, [])
      slot_attrs = Map.get(slot_attrs_by_component, fact.id, [])

      %{
        "name" => fact.data.name,
        "filePath" => file_path(fact.uri),
        "location" => location(fact),
        "attributesCount" => length(attrs),
        "slotsCount" => length(slots),
        "attributes" => Enum.map(attrs, &component_attr_payload/1),
        "slots" => Enum.map(slots, &component_slot_payload(&1, slot_attrs))
      }
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp list_routes(facts) do
    facts
    |> facts_by_kind(:route)
    |> Enum.map(fn fact ->
      action = optional_atom_string(fact.data.action)

      %{
        "verb" => Atom.to_string(fact.data.verb),
        "path" => fact.data.path,
        "controller" => fact.data.plug,
        "action" => action || "",
        "filePath" => file_path(fact.uri),
        "location" => location(fact),
        "scopePath" => fact.data.scope_path || "/",
        "liveModule" => live_module(fact),
        "liveAction" => live_action(fact)
      }
    end)
    |> Enum.sort_by(&{&1["scopePath"], &1["path"], &1["verb"]})
  end

  defp list_templates(facts) do
    facts
    |> facts_by_kind(:template)
    |> Enum.map(fn fact ->
      path = file_path(fact.uri)

      %{
        "name" => template_name(path),
        "format" => format_string(fact.data.format),
        "filePath" => path,
        "location" => location(fact),
        "module" => template_module(path)
      }
    end)
    |> Enum.sort_by(& &1["filePath"])
  end

  defp list_events(facts) do
    facts
    |> facts_by_kind(:live_event)
    |> Enum.map(fn fact ->
      %{
        "name" => fact.data.event,
        "type" => "handle_event",
        "filePath" => file_path(fact.uri),
        "location" => location(fact)
      }
    end)
    |> Enum.sort_by(&{&1["filePath"], &1["name"]})
  end

  defp list_live_view(facts) do
    events_by_module =
      facts
      |> facts_by_kind(:live_event)
      |> Enum.group_by(& &1.data.module)

    functions_by_module =
      facts
      |> facts_by_kind(:live_view_function)
      |> Enum.group_by(& &1.data.module)

    assigns_by_module =
      facts
      |> facts_by_kind(:assign)
      |> Enum.group_by(& &1.data.module)

    facts
    |> facts_by_kind(:live_view)
    |> Enum.map(fn fact ->
      events = Map.get(events_by_module, fact.data.module, [])
      functions = Map.get(functions_by_module, fact.data.module, [])
      assigns = Map.get(assigns_by_module, fact.data.module, [])

      %{
        "module" => fact.data.module,
        "filePath" => file_path(fact.uri),
        "location" => location(fact),
        "assigns" => live_view_assign_payloads(assigns),
        "functions" => live_view_function_payloads(functions, events)
      }
    end)
    |> Enum.sort_by(& &1["module"])
  end

  defp schema_field_payloads(schema_fact, fields, associations) do
    association_foreign_keys = association_foreign_keys(associations)
    explicit_field_names = MapSet.new(fields, & &1.data.name)

    generated_primary_key_payloads(schema_fact, explicit_field_names) ++
      Enum.map(fields, &schema_field_payload(&1, schema_fact, association_foreign_keys)) ++
      generated_association_field_payloads(
        schema_fact,
        associations,
        explicit_field_names
      )
  end

  defp schema_field_payload(fact, schema_fact, association_foreign_keys) do
    primary_key_name = primary_key_name(schema_fact)
    reference = Map.get(association_foreign_keys, fact.data.name)

    %{
      "name" => fact.data.name,
      "type" => type_string(fact.data.type),
      "elixirType" => inspect(fact.data.type),
      "primaryKey" => fact.data.name == primary_key_name,
      "foreignKey" => not is_nil(reference),
      "generated" => generated_field?(fact),
      "filePath" => file_path(fact.uri),
      "location" => location(fact)
    }
    |> maybe_put("references", reference)
  end

  defp generated_primary_key_payloads(%Fact{data: %{primary_key: false}}, _explicit_field_names),
    do: []

  defp generated_primary_key_payloads(%Fact{} = schema_fact, explicit_field_names) do
    primary_key = schema_fact.data.primary_key

    if MapSet.member?(explicit_field_names, primary_key.name) do
      []
    else
      [
        %{
          "name" => primary_key.name,
          "type" => type_string(primary_key.type),
          "elixirType" => inspect(primary_key.type),
          "primaryKey" => true,
          "foreignKey" => false,
          "generated" => true,
          "filePath" => file_path(schema_fact.uri),
          "location" => location(schema_fact)
        }
      ]
    end
  end

  defp generated_association_field_payloads(schema_fact, associations, explicit_field_names) do
    associations
    |> Enum.filter(&(&1.data.association == :belongs_to))
    |> Enum.filter(&association_defines_field?/1)
    |> Enum.reject(&MapSet.member?(explicit_field_names, association_foreign_key(&1)))
    |> Enum.map(fn association ->
      type = association_type(association, schema_fact)
      name = association_foreign_key(association)

      %{
        "name" => name,
        "type" => type_string(type),
        "elixirType" => inspect(type),
        "primaryKey" => false,
        "foreignKey" => true,
        "generated" => true,
        "references" => association.data.related,
        "filePath" => file_path(association.uri),
        "location" => location(association)
      }
    end)
  end

  defp association_foreign_keys(associations) do
    associations
    |> Enum.filter(&(&1.data.association == :belongs_to))
    |> Map.new(fn association ->
      {association_foreign_key(association), association.data.related}
    end)
  end

  defp primary_key_name(%Fact{data: %{primary_key: false}}), do: nil
  defp primary_key_name(%Fact{data: %{primary_key: primary_key}}), do: primary_key.name

  defp generated_field?(%Fact{data: %{options: options}}) do
    Keyword.has_key?(options || [], :generated_by)
  end

  defp association_foreign_key(%Fact{data: %{name: name, options: options}}) do
    options
    |> Keyword.get(:foreign_key, :"#{name}_id")
    |> Atom.to_string()
  end

  defp association_type(%Fact{data: %{options: options}}, schema_fact) do
    Keyword.get(options || [], :type, schema_fact.data.foreign_key_type)
  end

  defp association_defines_field?(%Fact{data: %{options: options}}) do
    Keyword.get(options || [], :define_field, true) != false
  end

  defp schema_association_payload(fact) do
    fact.data.options
    |> association_option_payload()
    |> Map.merge(%{
      "name" => fact.data.name,
      "fieldName" => fact.data.name,
      "foreignKey" => association_foreign_key(fact),
      "schema" => fact.data.related,
      "targetModule" => fact.data.related,
      "type" => Atom.to_string(fact.data.association),
      "cardinality" => association_cardinality(fact.data.association),
      "filePath" => file_path(fact.uri),
      "location" => location(fact)
    })
  end

  defp component_attr_payload(fact) do
    fact.data.options
    |> option_payload()
    |> Map.merge(%{
      "name" => fact.data.name,
      "type" => type_string(fact.data.type),
      "required" => required?(fact.data.options),
      "rawType" => inspect(fact.data.type),
      "filePath" => file_path(fact.uri),
      "location" => location(fact)
    })
  end

  defp component_slot_payload(slot, slot_attrs) do
    attrs =
      slot_attrs
      |> Enum.filter(&(&1.data.slot == slot.data.name))
      |> Enum.map(&component_attr_payload/1)

    slot.data.options
    |> option_payload()
    |> Map.merge(%{
      "name" => slot.data.name,
      "required" => required?(slot.data.options),
      "filePath" => file_path(slot.uri),
      "location" => location(slot),
      "attributes" => attrs
    })
  end

  defp live_event_function_payload(fact) do
    %{
      "name" => "handle_event",
      "type" => "handle_event",
      "eventName" => fact.data.event,
      "location" => location(fact)
    }
  end

  defp live_view_function_payloads(functions, events) do
    (Enum.map(functions, &live_view_function_payload/1) ++
       Enum.map(events, &live_event_function_payload/1))
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
      "filePath" => file_path(fact.uri),
      "location" => location(fact)
    }
  end

  defp live_view_assign_sort_key(payload) do
    location = payload["location"] || %{}
    {location["line"] || 0, location["character"] || 0, payload["name"] || ""}
  end

  defp live_view_function_payload(fact) do
    %{
      "name" => fact.data.name,
      "type" => Atom.to_string(fact.data.type),
      "location" => location(fact)
    }
  end

  defp live_view_function_sort_key(payload) do
    location = payload["location"] || %{}
    {live_view_function_rank(payload["type"]), location["line"] || 0, location["character"] || 0}
  end

  defp live_view_function_rank("mount"), do: 0
  defp live_view_function_rank("handle_params"), do: 1
  defp live_view_function_rank("render"), do: 2
  defp live_view_function_rank("handle_event"), do: 3
  defp live_view_function_rank("handle_info"), do: 4
  defp live_view_function_rank(_type), do: 5

  defp live_module(%Fact{data: %{verb: :live, plug: plug}}), do: plug
  defp live_module(_fact), do: nil

  defp live_action(%Fact{data: %{verb: :live, action: action}}), do: optional_atom_string(action)
  defp live_action(_fact), do: nil

  defp facts_by_kind(%Snapshot{} = snapshot, kind) do
    Snapshot.by_kind(snapshot, kind)
  end

  defp location(%Fact{range: %{start: start}}) do
    %{
      "line" => start.line,
      "character" => start.character
    }
  end

  defp file_path(uri) do
    case SupportURI.file_uri_to_path(uri) do
      {:ok, path} -> path
      {:error, _reason} -> uri
    end
  end

  defp option_payload(options) do
    options = options || []

    %{}
    |> maybe_put("default", option_value(options, :default, &inspect/1))
    |> maybe_put("values", option_value(options, :values, &values/1))
    |> maybe_put("doc", Keyword.get(options, :doc))
  end

  defp association_option_payload(options) do
    options = options || []

    %{}
    |> maybe_put("joinThrough", option_value(options, :join_through, &option_string/1))
    |> maybe_put("joinKeys", option_value(options, :join_keys, &inspect/1))
    |> maybe_put("onReplace", option_value(options, :on_replace, &value_string/1))
    |> maybe_put("defineField", option_value(options, :define_field, & &1))
  end

  defp option_value(options, key, transform) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> transform.(value)
      :error -> nil
    end
  end

  defp values(values) when is_list(values), do: Enum.map(values, &value_string/1)
  defp values(value), do: [value_string(value)]

  defp value_string(value) when is_atom(value), do: Atom.to_string(value)
  defp value_string(value), do: inspect(value)

  defp option_string(value) when is_binary(value), do: value
  defp option_string(value), do: inspect(value)

  defp required?(options), do: Keyword.get(options || [], :required, false) == true

  defp association_cardinality(:belongs_to), do: "many_to_one"
  defp association_cardinality(:has_one), do: "one_to_one"
  defp association_cardinality(:has_many), do: "one_to_many"
  defp association_cardinality(:many_to_many), do: "many_to_many"
  defp association_cardinality(:embeds_one), do: "one_to_one"
  defp association_cardinality(:embeds_many), do: "one_to_many"
  defp association_cardinality(_association), do: "unknown"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp type_string(type) when is_atom(type), do: Atom.to_string(type)
  defp type_string(type), do: inspect(type)

  defp optional_atom_string(nil), do: nil
  defp optional_atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp optional_atom_string(value) when is_binary(value), do: value

  defp format_string(format) when is_atom(format), do: Atom.to_string(format)
  defp format_string(format), do: to_string(format)

  defp template_name(path) do
    path
    |> Path.basename()
    |> Path.rootname()
  end

  defp template_module(path) do
    path
    |> Path.split()
    |> module_parts_from_template_path()
    |> case do
      [] -> ""
      parts -> Enum.join(parts, ".")
    end
  end

  defp module_parts_from_template_path(parts) do
    case Enum.split_while(parts, &(&1 != "lib")) do
      {_before_lib, ["lib", web_root | rest]} ->
        template_dirs =
          rest
          |> Enum.drop(-1)
          |> Enum.reject(&template_context_dir?/1)

        [module_segment(web_root) | Enum.map(template_dirs, &module_segment/1)]
        |> Enum.reject(&(&1 == ""))

      _path_without_lib ->
        []
    end
  end

  defp template_context_dir?(dir), do: dir in ["controllers", "live", "templates", "components"]

  defp module_segment(segment) do
    segment
    |> String.split("_")
    |> Enum.map(&module_word/1)
    |> Enum.join()
  end

  defp module_word(""), do: ""
  defp module_word("api"), do: "API"
  defp module_word("html"), do: "HTML"
  defp module_word("json"), do: "JSON"
  defp module_word(word), do: String.capitalize(word)
end
