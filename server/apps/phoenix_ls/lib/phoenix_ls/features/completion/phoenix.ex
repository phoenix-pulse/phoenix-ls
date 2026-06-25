defmodule PhoenixLS.Features.Completion.Phoenix do
  @moduledoc """
  Aggregates source-only Phoenix completion providers.
  """

  alias PhoenixLS.Features.Completion.{
    AssignFields,
    Assets,
    BuiltInComponents,
    ColocatedAssets,
    ControllerAssigns,
    ElixirFallback,
    FormFields,
    Hooks,
    HTMLAttributes,
    LiveView,
    LiveViewJS,
    PhxValues,
    Routes,
    Schemas,
    ScopedVariables,
    ShortcutSnippets,
    Snippets,
    SpecialAttrs,
    Templates,
    Uploads
  }

  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Features.Policy
  alias PhoenixLS.LSP.ServerConfig
  alias PhoenixLS.Support.Positions

  @spec complete(CursorContext.t(), [Fact.t()]) :: [GenLSP.Structures.CompletionItem.t()]
  def complete(%CursorContext{} = context, facts) when is_list(facts) do
    complete(context, facts, ServerConfig.default())
  end

  @spec complete(CursorContext.t(), [Fact.t()], ServerConfig.t()) :: [
          GenLSP.Structures.CompletionItem.t()
        ]
  def complete(%CursorContext{} = context, facts, %ServerConfig{} = config) when is_list(facts) do
    [
      Routes.complete(context, facts),
      Assets.complete(context, facts),
      Schemas.complete(context, facts),
      AssignFields.complete(context, facts),
      BuiltInComponents.complete(context, facts),
      HTMLAttributes.complete(context, facts),
      LiveView.complete(context, facts),
      LiveViewJS.complete(context, facts),
      ColocatedAssets.complete(context, facts),
      Hooks.complete(context, facts),
      SpecialAttrs.complete(context),
      Snippets.complete(context, facts),
      generic_elixir_completions(context, facts, config)
    ]
    |> List.flatten()
    |> uniq_by_label()
  end

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          GenLSP.Structures.CompletionItem.t()
        ]
  def complete(source, position, facts) when is_binary(source) and is_list(facts) do
    complete(nil, source, position, facts, ServerConfig.default())
  end

  @spec complete(String.t() | nil, String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          GenLSP.Structures.CompletionItem.t()
        ]
  def complete(uri, source, position, facts)
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    complete(uri, source, position, facts, ServerConfig.default())
  end

  @spec complete(String.t(), Positions.lsp_position(), [Fact.t()], ServerConfig.t()) :: [
          GenLSP.Structures.CompletionItem.t()
        ]
  def complete(source, position, facts, %ServerConfig{} = config)
      when is_binary(source) and is_list(facts) do
    complete(nil, source, position, facts, config)
  end

  @spec complete(
          String.t() | nil,
          String.t(),
          Positions.lsp_position(),
          [Fact.t()],
          ServerConfig.t()
        ) ::
          [
            GenLSP.Structures.CompletionItem.t()
          ]
  def complete(uri, source, position, facts, %ServerConfig{} = config)
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    case CursorContext.at(source, position) do
      {:ok, %CursorContext{} = context} -> complete(uri, source, position, context, facts, config)
      :error -> complete(uri, source, position, nil, facts, config)
    end
  end

  @spec complete(
          String.t() | nil,
          String.t(),
          Positions.lsp_position(),
          CursorContext.t() | nil,
          [Fact.t()],
          ServerConfig.t()
        ) :: [GenLSP.Structures.CompletionItem.t()]
  def complete(uri, source, position, context, facts, %ServerConfig{} = config)
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    complete_source_only(uri, source, position, context, facts, config)
    |> Kernel.++(context_completions(context, facts))
    |> uniq_by_label()
  end

  @spec complete_source_only(String.t(), Positions.lsp_position(), [Fact.t()]) :: [
          GenLSP.Structures.CompletionItem.t()
        ]
  def complete_source_only(source, position, facts) when is_binary(source) and is_list(facts) do
    complete_source_only(nil, source, position, facts, ServerConfig.default())
  end

  @spec complete_source_only(String.t() | nil, String.t(), Positions.lsp_position(), [Fact.t()]) ::
          [GenLSP.Structures.CompletionItem.t()]
  def complete_source_only(uri, source, position, facts)
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    complete_source_only(uri, source, position, facts, ServerConfig.default())
  end

  @spec complete_source_only(String.t(), Positions.lsp_position(), [Fact.t()], ServerConfig.t()) ::
          [GenLSP.Structures.CompletionItem.t()]
  def complete_source_only(source, position, facts, %ServerConfig{} = config)
      when is_binary(source) and is_list(facts) do
    complete_source_only(nil, source, position, facts, config)
  end

  @spec complete_source_only(
          String.t() | nil,
          String.t(),
          Positions.lsp_position(),
          [Fact.t()],
          ServerConfig.t()
        ) :: [GenLSP.Structures.CompletionItem.t()]
  def complete_source_only(uri, source, position, facts, %ServerConfig{} = config)
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    case CursorContext.at(source, position) do
      {:ok, %CursorContext{} = context} ->
        complete_source_only(uri, source, position, context, facts, config)

      :error ->
        complete_source_only(uri, source, position, nil, facts, config)
    end
  end

  @spec complete_source_only(
          String.t() | nil,
          String.t(),
          Positions.lsp_position(),
          CursorContext.t() | nil,
          [Fact.t()],
          ServerConfig.t()
        ) :: [GenLSP.Structures.CompletionItem.t()]
  def complete_source_only(uri, source, position, context, facts, %ServerConfig{})
      when (is_binary(uri) or is_nil(uri)) and is_binary(source) and is_list(facts) do
    source
    |> Routes.complete(uri, position, facts)
    |> Kernel.++(context_source_completions(uri, source, position, context, facts))
    |> Kernel.++(ShortcutSnippets.complete(source, position, facts))
    |> Kernel.++(Templates.complete(uri, source, position, facts))
    |> uniq_by_label()
  end

  defp generic_elixir_completions(context, facts, config) do
    if Policy.allow?(:completion, :generic_elixir, config) do
      ElixirFallback.complete(context, facts)
    else
      []
    end
  end

  defp context_completions(%CursorContext{} = context, facts) do
    Snippets.complete(context, facts) ++
      ColocatedAssets.complete(context, facts) ++
      Hooks.complete(context, facts)
  end

  defp context_completions(_context, _facts), do: []

  defp context_source_completions(uri, source, position, %CursorContext{} = context, facts) do
    SpecialAttrs.complete(context) ++
      AssignFields.complete(uri, context, facts) ++
      FormFields.complete(source, position, context, facts) ++
      PhxValues.complete(source, position, context, facts) ++
      ScopedVariables.complete(source, position, context) ++
      ControllerAssigns.complete(uri, context, facts) ++
      LiveView.complete(uri, source, position, context, facts) ++
      Uploads.complete(uri, source, position, context, facts)
  end

  defp context_source_completions(_uri, _source, _position, _context, _facts), do: []

  defp uniq_by_label(items) do
    items
    |> Enum.reduce({MapSet.new(), []}, fn item, {seen, acc} ->
      if MapSet.member?(seen, item.label) do
        {seen, acc}
      else
        {MapSet.put(seen, item.label), [item | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end
