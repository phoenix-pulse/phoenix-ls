defmodule PhoenixLS.LSP.Diagnostics do
  @moduledoc """
  Publishes textDocument diagnostics notifications for open documents.
  """

  alias GenLSP
  alias GenLSP.Enumerations.DiagnosticSeverity
  alias GenLSP.LSP

  alias GenLSP.Notifications.TextDocumentPublishDiagnostics

  alias GenLSP.Structures.{
    Diagnostic,
    Position,
    PublishDiagnosticsParams,
    Range
  }

  alias PhoenixLS.Features.Diagnostics, as: FeatureDiagnostics
  alias PhoenixLS.Features.Policy
  alias PhoenixLS.HEEx.Parser
  alias PhoenixLS.Index.{DependencyGraph, Snapshot}
  alias PhoenixLS.LSP.RequestContext
  alias PhoenixLS.Project.Engine
  alias PhoenixLS.Workspace.{Document, DocumentStore}

  @source "PhoenixLS"
  @timer_key :diagnostics_timers
  @debounce_ms 50
  @project_unavailable_message "Phoenix project engine is unavailable for this document"

  @spec schedule_publish(LSP.t(), DocumentStore.server(), String.t(), {:ok, Engine.t()} | :error) ::
          :ok
  def schedule_publish(%LSP{} = lsp, document_store, uri, project_engine) when is_binary(uri) do
    with {:ok, document} <- DocumentStore.fetch(document_store, uri),
         true <- diagnostic_document?(document) do
      cancel_timer(lsp, uri)

      token = make_ref()

      timer =
        Process.send_after(
          lsp.pid,
          {:phoenix_ls_publish_diagnostics, uri, token, document_store, project_engine},
          @debounce_ms
        )

      put_timer(lsp, uri, %{token: token, timer: timer})

      :ok
    else
      _other -> :ok
    end
  end

  @spec schedule_open_documents(LSP.t(), DocumentStore.server(), {:ok, Engine.t()} | :error) ::
          :ok
  def schedule_open_documents(%LSP{} = lsp, document_store, project_engine) do
    document_store
    |> DocumentStore.open_documents()
    |> Enum.filter(&diagnostic_document?/1)
    |> Enum.each(&schedule_publish(lsp, document_store, &1.uri, project_engine))

    :ok
  end

  @spec clear(LSP.t(), String.t()) :: :ok
  def clear(%LSP{} = lsp, uri) when is_binary(uri) do
    if diagnostic_uri?(uri) do
      cancel_timer(lsp, uri)
      delete_timer(lsp, uri)
      publish(lsp, uri, nil, [])
    else
      :ok
    end
  end

  @spec handle_info(term(), LSP.t()) :: {:noreply, LSP.t()}
  def handle_info(
        {:phoenix_ls_publish_diagnostics, uri, token, document_store, project_engine},
        %LSP{} = lsp
      ) do
    case current_token(lsp, uri) do
      ^token ->
        delete_timer(lsp, uri)
        publish_current_document(lsp, document_store, uri, project_engine)

      _stale_or_missing ->
        :ok
    end

    {:noreply, lsp}
  end

  def handle_info(
        {:phoenix_ls_index_changed, _uri, changed_kinds, document_store, project_engine},
        %LSP{} = lsp
      ) do
    document_store
    |> DocumentStore.open_documents()
    |> then(&DependencyGraph.affected_diagnostic_uris(changed_kinds, &1))
    |> Enum.each(&schedule_publish(lsp, document_store, &1, project_engine))

    {:noreply, lsp}
  end

  def handle_info(_message, %LSP{} = lsp), do: {:noreply, lsp}

  defp diagnostics(_document, :error, config) do
    if Policy.allow?(:diagnostics, :phoenix, config) do
      [project_unavailable_diagnostic()]
    else
      []
    end
  end

  defp diagnostics(%Document{} = document, {:ok, engine}, config) do
    snapshot = Snapshot.from_store(engine.index_store)
    facts = Snapshot.all(snapshot)

    cond do
      heex_document?(document) ->
        allowed_diagnostics(:heex_structure, config, fn -> heex_diagnostics(document, facts) end)

      elixir_document?(document) ->
        allowed_diagnostics(:phoenix, config, fn ->
          FeatureDiagnostics.diagnostics(document.uri, facts)
        end)

      true ->
        []
    end
  end

  defp allowed_diagnostics(feature_kind, config, fun) do
    if Policy.allow?(:diagnostics, feature_kind, config), do: fun.(), else: []
  end

  defp heex_diagnostics(%Document{uri: uri, text: text}, facts) do
    case Parser.parse(text) do
      {:ok, heex_document} -> FeatureDiagnostics.diagnostics(uri, heex_document, facts)
      {:error, reason} -> [parse_error_diagnostic(reason)]
    end
  end

  defp publish_current_document(lsp, document_store, uri, project_engine) do
    case DocumentStore.fetch(document_store, uri) do
      {:ok, %Document{} = document} ->
        config = lsp |> RequestContext.new() |> RequestContext.server_config!()
        diagnostics = diagnostics(document, project_engine, config)

        publish(lsp, document.uri, document.version, diagnostics)

      :error ->
        :ok
    end
  end

  defp publish(lsp, uri, nil, diagnostics) do
    GenLSP.notify(lsp, %TextDocumentPublishDiagnostics{
      params: %PublishDiagnosticsParams{
        uri: uri,
        diagnostics: diagnostics
      }
    })
  end

  defp publish(lsp, uri, version, diagnostics) do
    GenLSP.notify(lsp, %TextDocumentPublishDiagnostics{
      params: %PublishDiagnosticsParams{
        uri: uri,
        version: version,
        diagnostics: diagnostics
      }
    })
  end

  defp project_unavailable_diagnostic do
    %Diagnostic{
      range: zero_range(),
      severity: DiagnosticSeverity.warning(),
      code: "phoenix.project_unavailable",
      source: @source,
      message: @project_unavailable_message
    }
  end

  defp parse_error_diagnostic(reason) do
    %Diagnostic{
      range: zero_range(),
      severity: DiagnosticSeverity.error(),
      code: "phoenix.heex_parse_error",
      source: @source,
      message: "Unable to parse HEEx document: #{reason}"
    }
  end

  defp heex_document?(%Document{language_id: language_id, uri: uri}) do
    language_id in ["phoenix-heex", "heex"] or heex_uri?(uri)
  end

  defp elixir_document?(%Document{language_id: "elixir"}), do: true
  defp elixir_document?(%Document{uri: uri}), do: elixir_uri?(uri)

  defp diagnostic_document?(%Document{} = document) do
    heex_document?(document) or elixir_document?(document)
  end

  defp heex_uri?(uri) when is_binary(uri) do
    String.ends_with?(uri, [".heex", ".html.heex"])
  end

  defp elixir_uri?(uri) when is_binary(uri), do: String.ends_with?(uri, ".ex")
  defp diagnostic_uri?(uri), do: heex_uri?(uri) or elixir_uri?(uri)

  defp cancel_timer(lsp, uri) do
    case Map.fetch(timers(lsp), uri) do
      {:ok, %{timer: timer}} -> Process.cancel_timer(timer)
      :error -> false
    end
  end

  defp put_timer(lsp, uri, entry) do
    LSP.assign(lsp, [{@timer_key, Map.put(timers(lsp), uri, entry)}])
  end

  defp delete_timer(lsp, uri) do
    LSP.assign(lsp, [{@timer_key, Map.delete(timers(lsp), uri)}])
  end

  defp current_token(lsp, uri) do
    case Map.fetch(timers(lsp), uri) do
      {:ok, %{token: token}} -> token
      :error -> nil
    end
  end

  defp timers(lsp) do
    lsp
    |> LSP.assigns()
    |> Map.get(@timer_key, %{})
  end

  defp zero_range do
    position = %Position{line: 0, character: 0}
    %Range{start: position, end: position}
  end
end
