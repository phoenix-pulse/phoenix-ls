defmodule PhoenixLS.Introspection.LiveView.Uploads do
  @moduledoc """
  Source-only extraction of LiveView upload facts from Elixir AST.
  """

  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Introspection.Source
  alias PhoenixLS.LiveView.Uploads, as: UploadMetadata
  alias PhoenixLS.LiveView.Uploads.Upload

  @upload_callback_functions [
    :consume_uploaded_entries,
    :consume_uploaded_entry,
    :cancel_upload,
    :uploaded_entries,
    :upload_errors
  ]

  @spec facts(String.t(), [term()], String.t(), map()) :: [Fact.t()]
  def facts(module, expressions, uri, provenance)
      when is_binary(module) and is_list(expressions) and is_binary(uri) and is_map(provenance) do
    upload_definition_facts(module, expressions, uri, provenance) ++
      upload_callback_facts(module, expressions, uri, provenance)
  end

  defp upload_definition_facts(module, expressions, uri, provenance) do
    expressions
    |> Enum.flat_map(&upload_calls/1)
    |> Enum.uniq_by(fn {_range, name, _options} -> name end)
    |> Enum.map(fn {range, name, options} ->
      Fact.new!(
        kind: :upload,
        id: "#{module}:upload:#{name}",
        uri: uri,
        range: range,
        provenance: provenance,
        data: %Upload{
          module: module,
          name: name,
          options: options
        }
      )
    end)
  end

  defp upload_callback_facts(module, expressions, uri, provenance) do
    expressions
    |> Enum.flat_map(&upload_callback_calls/1)
    |> Enum.map(fn {range, name, role, function} ->
      Fact.new!(
        kind: :upload_usage,
        id: "#{module}:upload_usage:#{role}:#{name}:#{range.start.line}:#{range.start.character}",
        uri: uri,
        range: range,
        provenance: provenance,
        data: %{
          module: module,
          upload: name,
          role: role,
          attribute: nil,
          function: function,
          tag: nil
        }
      )
    end)
  end

  defp upload_calls({:allow_upload, meta, [_socket, name_ast, options_ast]}) do
    upload_call(meta, name_ast, options_ast)
  end

  defp upload_calls(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView]}, :allow_upload]},
          meta, [_socket, name_ast, options_ast]}
       ) do
    upload_call(meta, name_ast, options_ast)
  end

  defp upload_calls({:|>, _pipe_meta, [_socket, {:allow_upload, meta, [name_ast, options_ast]}]}) do
    upload_call(meta, name_ast, options_ast)
  end

  defp upload_calls(
         {:|>, _pipe_meta,
          [
            _socket,
            {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView]}, :allow_upload]},
             meta, [name_ast, options_ast]}
          ]}
       ) do
    upload_call(meta, name_ast, options_ast)
  end

  defp upload_calls(list) when is_list(list) do
    Enum.flat_map(list, &upload_calls/1)
  end

  defp upload_calls(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(&upload_calls/1)
  end

  defp upload_calls(_node), do: []

  defp upload_callback_calls({function, meta, args})
       when function in @upload_callback_functions and is_list(args) do
    case upload_callback(function, args) do
      {:ok, name_ast, role, arity} ->
        upload_callback_call(meta, name_ast, role, "#{function}/#{arity}")

      :error ->
        []
    end
  end

  defp upload_callback_calls(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView]}, function]}, meta,
          args}
       )
       when function in @upload_callback_functions and is_list(args) do
    case upload_callback(function, args) do
      {:ok, name_ast, role, arity} ->
        upload_callback_call(meta, name_ast, role, "Phoenix.LiveView.#{function}/#{arity}")

      :error ->
        []
    end
  end

  defp upload_callback_calls(list) when is_list(list) do
    Enum.flat_map(list, &upload_callback_calls/1)
  end

  defp upload_callback_calls(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(&upload_callback_calls/1)
  end

  defp upload_callback_calls(_node), do: []

  defp upload_callback(:consume_uploaded_entries, [_socket, name_ast, _callback]),
    do: {:ok, name_ast, :consume_uploaded_entries, 3}

  defp upload_callback(:consume_uploaded_entry, [_socket, name_ast, _entry, _callback]),
    do: {:ok, name_ast, :consume_uploaded_entry, 4}

  defp upload_callback(:cancel_upload, [_socket, name_ast, _ref]),
    do: {:ok, name_ast, :cancel_upload, 3}

  defp upload_callback(:uploaded_entries, [_socket, name_ast]),
    do: {:ok, name_ast, :uploaded_entries, 2}

  defp upload_callback(:upload_errors, [_socket, name_ast]),
    do: {:ok, name_ast, :upload_errors, 2}

  defp upload_callback(:upload_errors, [name_ast]),
    do: {:ok, name_ast, :upload_errors, 1}

  defp upload_callback(_function, _args), do: :error

  defp upload_callback_call(call_meta, name_ast, role, function) do
    range = source_range(name_ast, call_meta)

    case UploadMetadata.static_name(name_ast) do
      {:ok, name} -> [{range, name, role, function}]
      :error -> []
    end
  end

  defp upload_call(call_meta, name_ast, options_ast) do
    range = source_range(name_ast, call_meta)

    case UploadMetadata.static_name(name_ast) do
      {:ok, name} ->
        [{range, name, static_options(options_ast)}]

      :error ->
        []
    end
  end

  defp static_options(options) when is_list(options) do
    options
    |> Enum.flat_map(&static_option/1)
  end

  defp static_options(_options), do: []

  defp static_option({name, value}) when is_atom(name) do
    with true <- UploadMetadata.option_name?(name),
         {:ok, literal} <- Source.static_literal(value) do
      [{name, literal}]
    else
      _result -> []
    end
  end

  defp static_option(_option), do: []

  defp source_range({_form, meta, _args}, _call_meta) when is_list(meta) do
    Source.source_range(meta)
  end

  defp source_range(_name_ast, call_meta) do
    Source.source_range(call_meta)
  end
end
