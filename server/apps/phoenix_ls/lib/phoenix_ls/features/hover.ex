defmodule PhoenixLS.Features.Hover do
  @moduledoc """
  Hover content for Phoenix source facts.
  """

  alias GenLSP.Enumerations.MarkupKind
  alias GenLSP.Structures.{Hover, MarkupContent}

  alias PhoenixLS.Features.{
    BuiltInComponents,
    ComponentDocs,
    PhoenixFactLookup,
    SourceReferenceLookup
  }

  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.LiveView.{Attributes, JSCommands}
  alias PhoenixLS.Support.URI, as: SupportURI

  @spec hover(CursorContext.t(), [Fact.t()]) :: Hover.t() | nil
  def hover(%CursorContext{} = context, facts) do
    fact_hover(context, facts) || built_in_hover(context)
  end

  @spec hover_source(String.t(), CursorContext.lsp_position(), [Fact.t()]) :: Hover.t() | nil
  def hover_source(source, position, facts) when is_binary(source) and is_list(facts) do
    with {:ok, context} <- CursorContext.at(source, position) do
      source
      |> PhoenixFactLookup.cursor_fact(position, facts)
      |> hover_for_fact(facts)
      |> Kernel.||(built_in_hover(context))
    else
      _invalid_context -> nil
    end
  end

  @spec hover_source(String.t(), String.t(), CursorContext.lsp_position(), [Fact.t()]) ::
          Hover.t() | nil
  def hover_source(uri, source, position, facts)
      when is_binary(uri) and is_binary(source) and is_list(facts) do
    with {:ok, context} <- CursorContext.at(source, position) do
      uri
      |> PhoenixFactLookup.cursor_fact(source, position, facts)
      |> hover_for_fact(facts)
      |> Kernel.||(built_in_hover(context))
    else
      _invalid_context -> nil
    end
  end

  @spec hover(String.t(), %{line: non_neg_integer(), character: non_neg_integer()}, [Fact.t()]) ::
          Hover.t() | nil
  def hover(uri, position, facts) when is_binary(uri) and is_list(facts) do
    case reference_hover(uri, position, facts) do
      {:ok, hover} -> hover
      :not_found -> nil
    end
  end

  @spec reference_hover(
          String.t(),
          %{line: non_neg_integer(), character: non_neg_integer()},
          [Fact.t()]
        ) :: {:ok, Hover.t() | nil} | :not_found
  def reference_hover(uri, position, facts) when is_binary(uri) and is_list(facts) do
    case SourceReferenceLookup.target_result_at(uri, position, facts) do
      {:ok, fact} -> {:ok, hover_for_fact(fact, facts)}
      {:missing_target, _reference} -> {:ok, nil}
      :not_found -> :not_found
    end
  end

  defp hover_for_fact(nil, _facts), do: nil

  defp hover_for_fact(%Fact{} = fact, facts) do
    %Hover{
      contents: %MarkupContent{
        kind: MarkupKind.markdown(),
        value: markdown(fact, facts)
      }
    }
  end

  defp fact_hover(%CursorContext{} = context, facts) do
    context
    |> PhoenixFactLookup.cursor_fact(facts)
    |> hover_for_fact(facts)
  end

  defp built_in_hover(%CursorContext{kind: :tag_name, prefix: tag}) do
    tag
    |> BuiltInComponents.component_for_tag()
    |> built_in_component_hover()
  end

  defp built_in_hover(%CursorContext{kind: :attribute_name, tag: tag, prefix: prefix}) do
    built_in_attr =
      tag
      |> BuiltInComponents.attr_for_tag(prefix)
      |> built_in_attr_hover()

    built_in_attr || phoenix_attr_hover(prefix)
  end

  defp built_in_hover(%CursorContext{
         kind: :expression,
         attribute: "phx-" <> _binding,
         prefix: prefix
       }) do
    prefix
    |> JSCommands.command_for_prefix()
    |> js_command_hover()
  end

  defp built_in_hover(_context), do: nil

  defp built_in_component_hover(nil), do: nil

  defp built_in_component_hover(component) do
    component
    |> ComponentDocs.built_in_component_markdown(BuiltInComponents.attrs(component))
    |> hover_markdown()
  end

  defp built_in_attr_hover(nil), do: nil

  defp built_in_attr_hover(attr) do
    attr
    |> ComponentDocs.attr_markdown()
    |> hover_markdown()
  end

  defp phoenix_attr_hover(prefix) do
    case Attributes.completion_attr(prefix || "") do
      {name, detail, _insert_text} ->
        [
          code(name),
          detail,
          "Phoenix attribute"
        ]
        |> compact_join()
        |> hover_markdown()

      nil ->
        nil
    end
  end

  defp js_command_hover(nil), do: nil

  defp js_command_hover(command) do
    command
    |> JSCommands.markdown()
    |> hover_markdown()
  end

  defp hover_markdown(markdown) do
    %Hover{
      contents: %MarkupContent{
        kind: MarkupKind.markdown(),
        value: markdown
      }
    }
  end

  defp markdown(%Fact{kind: :component} = fact, facts),
    do: ComponentDocs.component_markdown(fact, facts)

  defp markdown(%Fact{kind: :component_attr} = fact, _facts),
    do: ComponentDocs.attr_markdown(fact)

  defp markdown(%Fact{kind: :component_slot} = fact, facts),
    do: ComponentDocs.slot_markdown(fact, facts)

  defp markdown(%Fact{kind: :component_slot_attr} = fact, _facts),
    do: ComponentDocs.slot_attr_markdown(fact)

  defp markdown(%Fact{kind: :route} = fact, _facts) do
    route =
      case fact.data.action do
        nil -> "#{fact.data.verb} \"#{fact.data.path}\", #{fact.data.plug}"
        action -> "#{fact.data.verb} \"#{fact.data.path}\", #{fact.data.plug}, :#{action}"
      end

    [
      code(route),
      "router #{fact.data.router}",
      route_target_line(fact.data),
      route_params_line(fact.data.path_params),
      route_pipelines_line(fact.data.pipelines)
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :template} = fact, _facts) do
    [
      code("template #{template_name(fact.uri)}"),
      "format #{inspect(fact.data.format)}",
      "module #{fact.data.module}",
      "type #{fact.data.kind}",
      file_path_line(fact.uri)
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :schema} = fact, _facts) do
    [
      code(schema_declaration(fact.data)),
      "module #{fact.data.module}",
      primary_key_line(fact.data.primary_key),
      "foreign key type #{inspect(fact.data.foreign_key_type)}"
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :schema_field} = fact, _facts) do
    [
      code("field :#{fact.data.name}, #{inspect(fact.data.type)}"),
      "schema #{fact.data.module}"
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :schema_association} = fact, facts) do
    [
      code("#{fact.data.association} :#{fact.data.name}, #{fact.data.related}"),
      "schema #{fact.data.module}",
      "target schema #{fact.data.related}",
      schema_fields_line(fact.data.related, facts)
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :assign} = fact, _facts) do
    [
      code("assign @#{fact.data.name}"),
      fact.data.module
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :controller_assign} = fact, _facts) do
    [
      code("controller assign @#{fact.data.name}"),
      "#{fact.data.module}##{fact.data.action}",
      "source #{fact.data.source}",
      "confidence #{fact.data.confidence}"
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :controller_plug_assign} = fact, _facts) do
    [
      code("controller plug assign @#{fact.data.name}"),
      "#{fact.data.module}.#{fact.data.plug}/2",
      "confidence #{fact.data.confidence}"
    ]
    |> compact_join()
  end

  defp markdown(%Fact{kind: :live_event} = fact, _facts) do
    [
      code(live_event_signature(fact.data)),
      "module #{fact.data.module}",
      file_path_line(fact.uri),
      location_line(fact.range)
    ]
    |> compact_join()
  end

  defp markdown(_fact, _facts), do: ""

  defp code(value) do
    "```elixir\n#{value}\n```"
  end

  defp template_name(uri) do
    case SupportURI.file_uri_to_path(uri) do
      {:ok, path} -> Path.basename(path)
      {:error, _reason} -> uri
    end
  end

  defp schema_declaration(%{source: nil}), do: "embedded_schema"
  defp schema_declaration(%{source: source}), do: ~s(schema "#{source}")

  defp primary_key_line(false), do: "primary key false"
  defp primary_key_line(%{name: name, type: type}), do: "primary key :#{name}, #{inspect(type)}"

  defp route_target_line(%{plug: plug, action: nil}), do: "target #{plug}"
  defp route_target_line(%{plug: plug, action: action}), do: "target #{plug} :#{action}"

  defp route_params_line([]), do: nil
  defp route_params_line(params), do: "params #{Enum.join(params, ", ")}"

  defp route_pipelines_line([]), do: nil
  defp route_pipelines_line(pipelines), do: "pipelines #{Enum.join(pipelines, ", ")}"

  defp schema_fields_line(module, facts) do
    fields =
      facts
      |> Enum.filter(&(&1.kind == :schema_field and &1.data.module == module))
      |> Enum.map(& &1.data.name)
      |> Enum.uniq()
      |> Enum.sort()

    case fields do
      [] -> nil
      fields -> "fields #{Enum.join(fields, ", ")}"
    end
  end

  defp file_path_line(uri) do
    case SupportURI.file_uri_to_path(uri) do
      {:ok, path} -> "file #{path}"
      {:error, _reason} -> nil
    end
  end

  defp live_event_signature(%{type: :handle_event, event: event}) do
    ~s|handle_event("#{event}", params, socket)|
  end

  defp live_event_signature(%{handler: handler, event: event}) do
    "#{handler} #{inspect(event)}"
  end

  defp location_line(%{start: %{line: line, character: character}}) do
    "location line #{line + 1}, character #{character + 1}"
  end

  defp location_line(_range), do: nil

  defp compact_join(values) do
    values
    |> List.flatten()
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
