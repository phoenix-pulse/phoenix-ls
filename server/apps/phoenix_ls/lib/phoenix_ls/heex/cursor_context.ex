defmodule PhoenixLS.HEEx.CursorContext do
  @moduledoc """
  Classifies HEEx cursor context for completion providers.

  This module is intentionally a small no-regex lexical classifier, not a full
  HEEx parser.
  """

  alias PhoenixLS.Support.Positions

  @enforce_keys [:kind, :prefix]
  defstruct [:kind, :tag, :attribute, :prefix, closing?: false]

  @type kind :: :text | :tag_name | :attribute_name | :attribute_value | :expression

  @type t :: %__MODULE__{
          kind: kind(),
          tag: String.t() | nil,
          attribute: String.t() | nil,
          prefix: String.t(),
          closing?: boolean()
        }

  @type lsp_position :: %{line: non_neg_integer(), character: non_neg_integer()}

  @spec at(String.t(), lsp_position()) :: {:ok, t()} | :error
  def at(source, position) when is_binary(source) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         {:ok, source_before_cursor} <- source_before_cursor(source, offset) do
      {:ok, source_before_cursor |> String.graphemes() |> classify()}
    end
  end

  def at(_source, _position), do: :error

  defp source_before_cursor(source, offset) when offset <= byte_size(source) do
    {:ok, binary_part(source, 0, offset)}
  end

  defp source_before_cursor(_source, _offset), do: :error

  defp classify(graphemes) do
    graphemes
    |> Enum.reduce(initial_state(), &step/2)
    |> context()
  end

  defp initial_state do
    %{
      state: :text,
      return_state: :text,
      brace_depth: 0,
      quote: nil,
      tag: nil,
      tag_prefix: "",
      attribute: nil,
      attribute_prefix: "",
      value_prefix: "",
      expression_prefix: "",
      closing?: false
    }
  end

  defp step("<", %{state: :text} = state) do
    %{state | state: :tag_name, tag: nil, tag_prefix: "", closing?: false}
  end

  defp step("{", %{state: :text} = state) do
    %{state | state: :expression, return_state: :text, brace_depth: 1, expression_prefix: ""}
  end

  defp step(_grapheme, %{state: :text} = state), do: state

  defp step("/", %{state: :tag_name, tag_prefix: ""} = state) do
    %{state | closing?: true}
  end

  defp step(">", %{state: :tag_name} = state), do: text_state(state)

  defp step(grapheme, %{state: :tag_name} = state) do
    cond do
      whitespace?(grapheme) ->
        tag = tag_name(state)

        %{state | state: :before_attribute, tag: tag, tag_prefix: tag}

      grapheme == "/" ->
        %{state | state: :before_attribute, tag: tag_name(state)}

      true ->
        %{state | tag_prefix: state.tag_prefix <> grapheme}
    end
  end

  defp step(grapheme, %{state: :before_attribute} = state) do
    cond do
      whitespace?(grapheme) ->
        state

      grapheme == ">" ->
        text_state(state)

      grapheme == "/" ->
        state

      grapheme == "{" ->
        %{
          state
          | state: :expression,
            return_state: :before_attribute,
            brace_depth: 1,
            expression_prefix: ""
        }

      true ->
        %{state | state: :attribute_name, attribute: nil, attribute_prefix: grapheme}
    end
  end

  defp step(grapheme, %{state: :attribute_name} = state) do
    cond do
      whitespace?(grapheme) ->
        %{state | state: :before_attribute, attribute: nil}

      grapheme == "=" ->
        %{state | state: :before_attribute_value, attribute: state.attribute_prefix}

      grapheme == ">" ->
        text_state(state)

      grapheme == "/" ->
        %{state | state: :before_attribute, attribute: nil}

      true ->
        %{state | attribute_prefix: state.attribute_prefix <> grapheme}
    end
  end

  defp step(grapheme, %{state: :before_attribute_value} = state) do
    cond do
      whitespace?(grapheme) ->
        state

      grapheme in ["\"", "'"] ->
        %{state | state: :attribute_value_quoted, quote: grapheme, value_prefix: ""}

      grapheme == "{" ->
        %{
          state
          | state: :expression,
            return_state: :before_attribute,
            brace_depth: 1,
            expression_prefix: ""
        }

      grapheme == ">" ->
        text_state(state)

      true ->
        %{state | state: :attribute_value_unquoted, value_prefix: grapheme}
    end
  end

  defp step(grapheme, %{state: :attribute_value_quoted} = state) do
    if grapheme == state.quote do
      %{state | state: :before_attribute, quote: nil, attribute: nil, value_prefix: ""}
    else
      %{state | value_prefix: state.value_prefix <> grapheme}
    end
  end

  defp step(grapheme, %{state: :attribute_value_unquoted} = state) do
    cond do
      whitespace?(grapheme) ->
        %{state | state: :before_attribute, attribute: nil, value_prefix: ""}

      grapheme == ">" ->
        text_state(state)

      true ->
        %{state | value_prefix: state.value_prefix <> grapheme}
    end
  end

  defp step("{", %{state: :expression} = state) do
    %{
      state
      | brace_depth: state.brace_depth + 1,
        expression_prefix: state.expression_prefix <> "{"
    }
  end

  defp step("}", %{state: :expression, brace_depth: 1} = state) do
    case state.return_state do
      :before_attribute -> %{state | state: :before_attribute, brace_depth: 0, attribute: nil}
      :text -> text_state(state)
    end
  end

  defp step("}", %{state: :expression} = state) do
    %{
      state
      | brace_depth: max(state.brace_depth - 1, 0),
        expression_prefix: state.expression_prefix <> "}"
    }
  end

  defp step(grapheme, %{state: :expression} = state) do
    %{state | expression_prefix: state.expression_prefix <> grapheme}
  end

  defp context(%{state: :tag_name} = state) do
    %__MODULE__{
      kind: :tag_name,
      tag: tag_name(state),
      prefix: state.tag_prefix,
      closing?: state.closing?
    }
  end

  defp context(%{state: :before_attribute} = state) do
    %__MODULE__{
      kind: :attribute_name,
      tag: state.tag,
      prefix: "",
      closing?: state.closing?
    }
  end

  defp context(%{state: :attribute_name} = state) do
    %__MODULE__{
      kind: :attribute_name,
      tag: state.tag,
      prefix: state.attribute_prefix,
      closing?: state.closing?
    }
  end

  defp context(%{state: :before_attribute_value} = state) do
    %__MODULE__{
      kind: :attribute_value,
      tag: state.tag,
      attribute: state.attribute,
      prefix: "",
      closing?: state.closing?
    }
  end

  defp context(%{state: state_name} = state)
       when state_name in [:attribute_value_quoted, :attribute_value_unquoted] do
    %__MODULE__{
      kind: :attribute_value,
      tag: state.tag,
      attribute: state.attribute,
      prefix: state.value_prefix,
      closing?: state.closing?
    }
  end

  defp context(%{state: :expression} = state) do
    %__MODULE__{
      kind: :expression,
      tag: expression_tag(state),
      attribute: expression_attribute(state),
      prefix: state.expression_prefix,
      closing?: state.closing?
    }
  end

  defp context(_state), do: %__MODULE__{kind: :text, prefix: ""}

  defp expression_tag(%{return_state: :before_attribute, tag: tag}), do: tag
  defp expression_tag(_state), do: nil

  defp expression_attribute(%{return_state: :before_attribute, attribute: attribute}),
    do: attribute

  defp expression_attribute(_state), do: nil

  defp tag_name(%{tag_prefix: ""}), do: nil
  defp tag_name(%{tag_prefix: tag_prefix}), do: tag_prefix

  defp text_state(state) do
    %{state | state: :text, return_state: :text, brace_depth: 0, quote: nil}
  end

  defp whitespace?(grapheme), do: grapheme in [" ", "\t", "\n", "\r"]
end
