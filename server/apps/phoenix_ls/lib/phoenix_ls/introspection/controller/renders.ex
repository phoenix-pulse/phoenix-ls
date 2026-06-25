defmodule PhoenixLS.Introspection.Controller.Renders do
  @moduledoc """
  Extracts controller render, assign, and layout facts from action bodies.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Controller.{Actions, Assign, Layout, Render}
  alias PhoenixLS.Introspection.Source
  alias PhoenixLS.Introspection.Template.RenderCall

  @spec facts(String.t(), [Actions.Entry.t()], String.t(), map()) :: [Fact.t()]
  def facts(module, actions, uri, provenance)
      when is_binary(module) and is_list(actions) and is_binary(uri) and is_map(provenance) do
    Enum.flat_map(actions, fn %Actions.Entry{} = action ->
      render_facts(module, action, uri, provenance) ++
        assign_facts(module, action, uri, provenance) ++
        layout_facts(module, action, uri, provenance)
    end)
  end

  defp render_facts(module, %Actions.Entry{} = action, uri, provenance) do
    action.body
    |> render_calls()
    |> Enum.map(fn %{range: range, template: template, format: format, assigns: assigns} ->
      Fact.new!(
        kind: :controller_render,
        id:
          "#{module}:render:#{action.name}:#{template}:#{range.start.line}:#{range.start.character}",
        uri: uri,
        range: range,
        provenance: provenance,
        data: %Render{
          module: module,
          action: action.name,
          template: template,
          format: format,
          candidate_uris: RenderCall.candidate_uris(uri, template, format),
          assigns: assigns,
          confidence: :exact
        }
      )
    end)
  end

  defp assign_facts(module, %Actions.Entry{} = action, uri, provenance) do
    direct_assigns =
      action.body
      |> assign_calls()
      |> Enum.map(&Map.put(&1, :source, :assign))

    render_assigns =
      action.body
      |> render_calls()
      |> Enum.flat_map(fn render ->
        Enum.map(render.assign_entries, fn assign ->
          Map.merge(assign, %{range: render.range, source: :render_keyword})
        end)
      end)

    (direct_assigns ++ render_assigns)
    |> Enum.map(fn %{range: range, name: name, source: source} = assign ->
      Fact.new!(
        kind: :controller_assign,
        id:
          "#{module}:assign:#{action.name}:#{name}:#{source}:#{range.start.line}:#{range.start.character}",
        uri: uri,
        range: range,
        provenance: provenance,
        data: %Assign{
          module: module,
          action: action.name,
          name: name,
          source: source,
          confidence: :exact,
          schema_source: Map.get(assign, :schema_source)
        }
      )
    end)
  end

  defp layout_facts(module, %Actions.Entry{} = action, uri, provenance) do
    action.body
    |> layout_calls()
    |> Enum.map(fn %{range: range, layout: layout, source: source} ->
      Fact.new!(
        kind: :controller_layout,
        id:
          "#{module}:layout:#{action.name}:#{layout}:#{range.start.line}:#{range.start.character}",
        uri: uri,
        range: range,
        provenance: provenance,
        data: %Layout{
          module: module,
          action: action.name,
          layout: layout,
          source: source,
          confidence: :exact
        }
      )
    end)
  end

  @spec assign_entries(term()) :: [%{range: GenLSP.Structures.Range.t(), name: String.t()}]
  def assign_entries(ast), do: assign_calls(ast)

  defp render_calls(ast) do
    ast
    |> collect_nodes()
    |> Enum.flat_map(&render_call/1)
  end

  defp render_call({:render, meta, args}) when is_list(args) do
    render_from_args(meta, args)
  end

  defp render_call({{:., _dot_meta, [module_ast, :render]}, meta, args}) when is_list(args) do
    if phoenix_controller_module?(module_ast) do
      render_from_args(meta, remote_render_args(args))
    else
      []
    end
  end

  defp render_call(_node), do: []

  defp render_from_args(meta, args) do
    with {:ok, template, format, rest} <- render_template(args) do
      assign_entries = render_keyword_assigns(rest)

      [
        %{
          range: Source.source_range(meta),
          template: template,
          format: format,
          assigns: Enum.map(assign_entries, & &1.name),
          assign_entries: assign_entries
        }
      ]
    else
      _not_static_render -> []
    end
  end

  defp remote_render_args([_conn_ast, _view_ast, template_ast | rest]), do: [template_ast | rest]
  defp remote_render_args(args), do: args

  defp render_template([template_ast]), do: template_literal(template_ast, [])

  defp render_template([template_ast, keyword]) when is_list(keyword) do
    if Keyword.keyword?(keyword) do
      template_literal(template_ast, [keyword])
    else
      :error
    end
  end

  defp render_template([_conn_ast, template_ast | rest]), do: template_literal(template_ast, rest)
  defp render_template(_args), do: :error

  defp template_literal(template, rest) when is_atom(template) do
    {:ok, Atom.to_string(template), "html", rest}
  end

  defp template_literal(template, rest) when is_binary(template) do
    {:ok, template_name(template), template_format(template), rest}
  end

  defp template_literal(_template, _rest), do: :error

  defp render_keyword_assigns(args) do
    args
    |> Enum.find(&Keyword.keyword?/1)
    |> case do
      nil -> []
      keyword -> keyword_assign_entries(nil, keyword)
    end
  end

  defp assign_calls(ast) do
    ast
    |> collect_nodes()
    |> Enum.flat_map(&assign_call/1)
  end

  defp assign_call({:assign, meta, args}) when is_list(args) do
    range = Source.source_range(meta)

    case args do
      [name_ast, value_ast] when is_atom(name_ast) ->
        assign_entries(range, static_names(name_ast), value_ast)

      [_conn_ast, keyword] when is_list(keyword) ->
        keyword_assign_entries(range, keyword)

      [keyword] when is_list(keyword) ->
        keyword_assign_entries(range, keyword)

      [_conn_ast, name_ast, value_ast] ->
        assign_entries(range, static_names(name_ast), value_ast)

      _args ->
        []
    end
  end

  defp assign_call(_node), do: []

  defp layout_calls(ast) do
    ast
    |> collect_nodes()
    |> Enum.flat_map(&layout_call/1)
  end

  defp layout_call({:put_layout, meta, args}) when is_list(args) do
    args
    |> Enum.find(&Keyword.keyword?/1)
    |> case do
      keyword when is_list(keyword) ->
        keyword
        |> Keyword.get(:html)
        |> layout_name()
        |> case do
          {:ok, layout} ->
            [%{range: Source.source_range(meta), layout: layout, source: :put_layout}]

          :error ->
            []
        end

      _missing_layout ->
        []
    end
  end

  defp layout_call(_node), do: []

  defp collect_nodes(ast) do
    {_ast, nodes} =
      Macro.prewalk(ast, [], fn node, acc ->
        {node, [node | acc]}
      end)

    Enum.reverse(nodes)
  end

  defp keyword_assign_entries(range, keyword) do
    if Keyword.keyword?(keyword) do
      keyword
      |> Enum.flat_map(fn
        {name, value_ast} when is_atom(name) ->
          assign_entries(range, [Atom.to_string(name)], value_ast)

        _entry ->
          []
      end)
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(& &1.name)
    else
      []
    end
  end

  defp assign_entries(range, names, value_ast) do
    Enum.map(names, fn name ->
      %{range: range, name: name, schema_source: schema_source(value_ast)}
    end)
  end

  defp static_names(name) when is_atom(name), do: [Atom.to_string(name)]

  defp static_names(names) when is_list(names) do
    Enum.flat_map(names, &static_names/1)
  end

  defp static_names(_name), do: []

  defp schema_source({name, _meta, nil}) when is_atom(name), do: Atom.to_string(name)
  defp schema_source(_ast), do: nil

  defp layout_name(name) when is_atom(name), do: {:ok, Atom.to_string(name)}
  defp layout_name(name) when is_binary(name), do: {:ok, name}
  defp layout_name(_name), do: :error

  defp phoenix_controller_module?({:__aliases__, _meta, [:Phoenix, :Controller]}), do: true
  defp phoenix_controller_module?(_module_ast), do: false

  defp template_name(value) do
    value
    |> Path.basename()
    |> Path.rootname()
  end

  defp template_format(value) do
    case value |> Path.basename() |> Path.extname() do
      "." <> format -> format
      "" -> "html"
    end
  end
end
