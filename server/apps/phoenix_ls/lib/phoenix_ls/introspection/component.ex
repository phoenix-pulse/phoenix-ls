defmodule PhoenixLS.Introspection.Component do
  @moduledoc """
  Source-only extraction helpers for Phoenix components.
  """

  alias GenLSP.Structures.Range
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.LiveView
  alias PhoenixLS.Introspection.Source

  defmodule Component do
    @moduledoc """
    Typed function component fact payload.
    """

    @enforce_keys [:module, :name, :arity, :visibility, :type]
    defstruct [:module, :name, :arity, :visibility, :type, :doc]
  end

  defmodule Attribute do
    @moduledoc """
    Typed component attr fact payload.
    """

    @enforce_keys [:component, :module, :component_name, :name, :type, :options]
    defstruct [:component, :module, :component_name, :name, :type, :options]
  end

  defmodule Slot do
    @moduledoc """
    Typed component slot fact payload.
    """

    @enforce_keys [:component, :module, :component_name, :name, :options]
    defstruct [:component, :module, :component_name, :name, :options]
  end

  defmodule SlotAttribute do
    @moduledoc """
    Typed component slot attr fact payload.
    """

    @enforce_keys [:component, :module, :component_name, :slot, :name, :type, :options]
    defstruct [:component, :module, :component_name, :slot, :name, :type, :options]
  end

  defmodule Alias do
    @moduledoc """
    Typed component alias fact payload.
    """

    @enforce_keys [:module, :target, :as]
    defstruct [:module, :target, :as]
  end

  defmodule Import do
    @moduledoc """
    Typed component import fact payload.
    """

    @enforce_keys [:module, :target]
    defstruct [:module, :target, :only, :except]
  end

  defmodule Use do
    @moduledoc """
    Typed Phoenix web macro use fact payload for component availability.
    """

    @enforce_keys [:module, :target, :macro]
    defstruct [:module, :target, :macro]
  end

  defmodule MacroImport do
    @moduledoc """
    Typed component import fact payload declared inside a Phoenix web macro.
    """

    @enforce_keys [:module, :macro, :target]
    defstruct [:module, :macro, :target, :only, :except]
  end

  @component_web_macros [:html, :live_view, :live_component]

  @spec facts_for_module_body(String.t(), term(), String.t(), map()) :: [Fact.t()]
  def facts_for_module_body(module, body_ast, uri, provenance)
      when is_binary(module) and is_binary(uri) and is_map(provenance) do
    body_ast
    |> Source.top_level_expressions()
    |> Enum.reduce(
      initial_state(LiveView.live_view_module?(body_ast)),
      &collect_expression(&1, &2, module, uri, provenance)
    )
    |> Map.fetch!(:facts)
  end

  @spec function_component_fact(
          String.t(),
          String.t(),
          non_neg_integer(),
          :public | :private,
          term(),
          Range.t(),
          String.t(),
          map()
        ) :: {:ok, Fact.t()} | :none
  def function_component_fact(module, name, 1, :public, body_ast, range, uri, provenance)
      when is_binary(module) and is_binary(name) and is_binary(uri) and is_map(provenance) do
    if contains_heex_sigil?(body_ast) do
      {:ok, component_fact(module, name, range, uri, provenance, nil)}
    else
      :none
    end
  end

  def function_component_fact(
        _module,
        _name,
        _arity,
        _visibility,
        _body_ast,
        _range,
        _uri,
        _provenance
      ),
      do: :none

  defp initial_state(live_view?) do
    %{
      attrs: [],
      slots: [],
      facts: [],
      doc: nil,
      live_view?: live_view?
    }
  end

  defp collect_expression({:alias, meta, args}, state, module, uri, provenance) do
    case component_alias_fact(module, meta, args, uri, provenance) do
      {:ok, fact} -> append_fact(state, fact)
      :error -> state
    end
  end

  defp collect_expression({:import, meta, args}, state, module, uri, provenance) do
    case component_import_fact(module, meta, args, uri, provenance) do
      {:ok, fact} -> append_fact(state, fact)
      :error -> state
    end
  end

  defp collect_expression({:use, meta, args}, state, module, uri, provenance) do
    case component_use_fact(module, meta, args, uri, provenance) do
      {:ok, fact} -> append_fact(state, fact)
      :error -> state
    end
  end

  defp collect_expression(
         {:@, _meta, [{:doc, _doc_meta, [doc]}]},
         state,
         _module,
         _uri,
         _provenance
       )
       when is_binary(doc) do
    %{state | doc: doc}
  end

  defp collect_expression({:attr, meta, args}, state, _module, _uri, _provenance) do
    case attr_declaration(meta, args) do
      {:ok, attr} -> %{state | attrs: state.attrs ++ [attr]}
      :error -> state
    end
  end

  defp collect_expression({:slot, meta, args}, state, _module, _uri, _provenance) do
    case slot_declaration(meta, args) do
      {:ok, slot} -> %{state | slots: state.slots ++ [slot]}
      :error -> state
    end
  end

  defp collect_expression({visibility, meta, [head, body]}, state, module, uri, provenance)
       when visibility in [:def, :defp] do
    state =
      state
      |> append_facts(macro_import_facts(visibility, head, body, module, uri, provenance))

    with {:ok, name, arity} <- function_signature(head),
         visibility <- visibility(visibility),
         range <- Source.source_range(meta),
         false <- live_view_render?(state, name, arity),
         {:ok, component_fact} <-
           function_component_fact(module, name, arity, visibility, body, range, uri, provenance) do
      component_fact = put_component_doc(component_fact, state.doc)
      component_id = component_fact.id

      component_facts =
        declaration_facts(component_id, module, name, state.attrs, state.slots, uri, provenance)

      %{
        state
        | attrs: [],
          slots: [],
          doc: nil,
          facts: state.facts ++ [component_fact | component_facts]
      }
    else
      _not_component -> %{state | doc: nil}
    end
  end

  defp collect_expression(_expression, state, _module, _uri, _provenance), do: state

  defp live_view_render?(%{live_view?: true}, "render", 1), do: true
  defp live_view_render?(_state, _name, _arity), do: false

  defp append_fact(state, fact) do
    %{state | facts: state.facts ++ [fact]}
  end

  defp append_facts(state, []), do: state

  defp append_facts(state, facts) do
    %{state | facts: state.facts ++ facts}
  end

  defp declaration_facts(component_id, module, component_name, attrs, slots, uri, provenance) do
    attr_facts =
      Enum.map(attrs, fn attr ->
        component_attr_fact(component_id, module, component_name, attr, uri, provenance)
      end)

    slot_facts =
      Enum.flat_map(slots, fn slot ->
        slot_fact =
          component_slot_fact(component_id, module, component_name, slot, uri, provenance)

        slot_attr_facts =
          Enum.map(slot.attrs, fn attr ->
            component_slot_attr_fact(
              component_id,
              module,
              component_name,
              slot,
              attr,
              uri,
              provenance
            )
          end)

        [slot_fact | slot_attr_facts]
      end)

    attr_facts ++ slot_facts
  end

  defp component_fact(module, name, range, uri, provenance, doc) do
    Fact.new!(
      kind: :component,
      id: "#{module}.#{name}/1",
      uri: uri,
      range: range,
      provenance: provenance,
      data: %Component{
        module: module,
        name: name,
        arity: 1,
        visibility: :public,
        type: :function,
        doc: doc
      }
    )
  end

  defp put_component_doc(fact, nil), do: fact

  defp put_component_doc(fact, doc) do
    %{fact | data: %{fact.data | doc: doc}}
  end

  defp component_attr_fact(component_id, module, component_name, attr, uri, provenance) do
    Fact.new!(
      kind: :component_attr,
      id: "#{component_id}:attr:#{attr.name}",
      uri: uri,
      range: attr.range,
      provenance: provenance,
      data: %Attribute{
        component: component_id,
        module: module,
        component_name: component_name,
        name: attr.name,
        type: attr.type,
        options: attr.options
      }
    )
  end

  defp component_slot_fact(component_id, module, component_name, slot, uri, provenance) do
    Fact.new!(
      kind: :component_slot,
      id: "#{component_id}:slot:#{slot.name}",
      uri: uri,
      range: slot.range,
      provenance: provenance,
      data: %Slot{
        component: component_id,
        module: module,
        component_name: component_name,
        name: slot.name,
        options: slot.options
      }
    )
  end

  defp component_slot_attr_fact(component_id, module, component_name, slot, attr, uri, provenance) do
    Fact.new!(
      kind: :component_slot_attr,
      id: "#{component_id}:slot:#{slot.name}:attr:#{attr.name}",
      uri: uri,
      range: attr.range,
      provenance: provenance,
      data: %SlotAttribute{
        component: component_id,
        module: module,
        component_name: component_name,
        slot: slot.name,
        name: attr.name,
        type: attr.type,
        options: attr.options
      }
    )
  end

  defp component_alias_fact(module, meta, [target_ast], uri, provenance) do
    component_alias_fact(module, meta, [target_ast, []], uri, provenance)
  end

  defp component_alias_fact(module, meta, [target_ast, options], uri, provenance)
       when is_list(options) do
    with {:ok, target} <- Source.alias_to_string(target_ast) do
      as = options |> Keyword.get(:as) |> alias_as(target)

      {:ok,
       Fact.new!(
         kind: :component_alias,
         id: "#{module}:alias:#{target}",
         uri: uri,
         range: Source.source_range(meta),
         provenance: provenance,
         data: %Alias{
           module: module,
           target: target,
           as: as
         }
       )}
    end
  end

  defp component_alias_fact(_module, _meta, _args, _uri, _provenance), do: :error

  defp component_import_fact(module, meta, [target_ast], uri, provenance) do
    component_import_fact(module, meta, [target_ast, []], uri, provenance)
  end

  defp component_import_fact(module, meta, [target_ast, options], uri, provenance)
       when is_list(options) do
    with {:ok, target} <- Source.alias_to_string(target_ast) do
      {:ok,
       Fact.new!(
         kind: :component_import,
         id: "#{module}:import:#{target}",
         uri: uri,
         range: Source.source_range(meta),
         provenance: provenance,
         data: %Import{
           module: module,
           target: target,
           only: Keyword.get(options, :only),
           except: Keyword.get(options, :except)
         }
       )}
    end
  end

  defp component_import_fact(_module, _meta, _args, _uri, _provenance), do: :error

  defp component_use_fact(module, meta, [target_ast, macro], uri, provenance)
       when is_atom(macro) and macro in @component_web_macros do
    with {:ok, target} <- Source.alias_to_string(target_ast) do
      {:ok,
       Fact.new!(
         kind: :component_use,
         id: "#{module}:use:#{target}:#{macro}",
         uri: uri,
         range: Source.source_range(meta),
         provenance: provenance,
         data: %Use{
           module: module,
           target: target,
           macro: macro
         }
       )}
    end
  end

  defp component_use_fact(_module, _meta, _args, _uri, _provenance), do: :error

  defp macro_import_facts(:def, head, body, module, uri, provenance) do
    with {:ok, macro, 0} <- function_signature(head),
         {:ok, macro} <- component_web_macro(macro),
         {:ok, quote_body} <- quote_body(body) do
      quote_body
      |> Source.top_level_expressions()
      |> Enum.flat_map(&macro_import_fact(module, macro, &1, uri, provenance))
    else
      _not_component_web_macro -> []
    end
  end

  defp macro_import_facts(_visibility, _head, _body, _module, _uri, _provenance), do: []

  defp macro_import_fact(module, macro, {:import, meta, args}, uri, provenance) do
    case component_macro_import_fact(module, macro, meta, args, uri, provenance) do
      {:ok, fact} -> [fact]
      :error -> []
    end
  end

  defp macro_import_fact(_module, _macro, _expression, _uri, _provenance), do: []

  defp component_macro_import_fact(module, macro, meta, [target_ast], uri, provenance) do
    component_macro_import_fact(module, macro, meta, [target_ast, []], uri, provenance)
  end

  defp component_macro_import_fact(module, macro, meta, [target_ast, options], uri, provenance)
       when is_list(options) do
    with {:ok, target} <- Source.alias_to_string(target_ast) do
      {:ok,
       Fact.new!(
         kind: :component_macro_import,
         id: "#{module}:#{macro}:import:#{target}",
         uri: uri,
         range: Source.source_range(meta),
         provenance: provenance,
         data: %MacroImport{
           module: module,
           macro: macro,
           target: target,
           only: Keyword.get(options, :only),
           except: Keyword.get(options, :except)
         }
       )}
    end
  end

  defp component_macro_import_fact(_module, _macro, _meta, _args, _uri, _provenance),
    do: :error

  defp component_web_macro(name) when is_atom(name), do: component_web_macro(Atom.to_string(name))

  defp component_web_macro(name) when is_binary(name) do
    Enum.find_value(@component_web_macros, :error, fn macro ->
      if Atom.to_string(macro) == name, do: {:ok, macro}
    end)
  end

  defp quote_body(do: {:quote, _meta, [options]}) when is_list(options) do
    case Keyword.fetch(options, :do) do
      {:ok, body} -> {:ok, body}
      :error -> :error
    end
  end

  defp quote_body(_body), do: :error

  defp alias_as(nil, target) do
    target
    |> String.split(".")
    |> List.last()
  end

  defp alias_as(atom, _target) when is_atom(atom), do: Atom.to_string(atom)
  defp alias_as(_other, target), do: alias_as(nil, target)

  defp attr_declaration(meta, [name, type]) when is_atom(name) do
    {:ok,
     %{name: Atom.to_string(name), type: type, options: [], range: Source.source_range(meta)}}
  end

  defp attr_declaration(meta, [name, type, options]) when is_atom(name) and is_list(options) do
    {:ok,
     %{
       name: Atom.to_string(name),
       type: type,
       options: normalize_options(options),
       range: Source.source_range(meta)
     }}
  end

  defp attr_declaration(_meta, _args), do: :error

  defp slot_declaration(meta, [name]) when is_atom(name) do
    {:ok, %{name: Atom.to_string(name), options: [], attrs: [], range: Source.source_range(meta)}}
  end

  defp slot_declaration(meta, [name, options_or_block])
       when is_atom(name) and is_list(options_or_block) do
    {options, block} = slot_options_and_block(options_or_block)

    {:ok,
     %{
       name: Atom.to_string(name),
       options: normalize_options(options),
       attrs: slot_attr_declarations(block),
       range: Source.source_range(meta)
     }}
  end

  defp slot_declaration(meta, [name, options, [do: block]])
       when is_atom(name) and is_list(options) do
    {:ok,
     %{
       name: Atom.to_string(name),
       options: options,
       attrs: slot_attr_declarations(block),
       range: Source.source_range(meta)
     }}
  end

  defp slot_declaration(_meta, _args), do: :error

  defp slot_options_and_block(options_or_block) do
    case Keyword.fetch(options_or_block, :do) do
      {:ok, block} -> {options_or_block |> Keyword.delete(:do) |> normalize_options(), block}
      :error -> {normalize_options(options_or_block), nil}
    end
  end

  defp slot_attr_declarations(nil), do: []

  defp slot_attr_declarations(block) do
    block
    |> Source.top_level_expressions()
    |> Enum.flat_map(fn
      {:attr, meta, args} ->
        case attr_declaration(meta, args) do
          {:ok, attr} -> [attr]
          :error -> []
        end

      _expression ->
        []
    end)
  end

  defp normalize_options(options) when is_list(options) do
    Enum.map(options, fn
      {key, value} when is_atom(key) -> {key, normalize_option_value(value)}
      other -> other
    end)
  end

  defp normalize_option_value(value) do
    case Source.static_literal(value) do
      {:ok, literal} -> literal
      :error -> value
    end
  end

  defp function_signature({:when, _meta, [head | _guards]}) do
    function_signature(head)
  end

  defp function_signature({name, _meta, args}) when is_atom(name) and is_list(args) do
    {:ok, Atom.to_string(name), length(args)}
  end

  defp function_signature({name, _meta, nil}) when is_atom(name) do
    {:ok, Atom.to_string(name), 0}
  end

  defp function_signature(_head), do: :error

  defp contains_heex_sigil?({:sigil_H, _meta, _args}), do: true

  defp contains_heex_sigil?(list) when is_list(list) do
    Enum.any?(list, &contains_heex_sigil?/1)
  end

  defp contains_heex_sigil?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&contains_heex_sigil?/1)
  end

  defp contains_heex_sigil?(_node), do: false

  defp visibility(:def), do: :public
  defp visibility(:defp), do: :private
end
