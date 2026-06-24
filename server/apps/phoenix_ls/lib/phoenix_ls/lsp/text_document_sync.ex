defmodule PhoenixLS.LSP.TextDocumentSync do
  @moduledoc """
  Handles LSP text document synchronization notifications.
  """

  alias GenLSP.LSP

  alias GenLSP.Notifications.{
    TextDocumentDidChange,
    TextDocumentDidClose,
    TextDocumentDidOpen
  }

  alias PhoenixLS.Index.Indexer
  alias PhoenixLS.LSP.Diagnostics
  alias PhoenixLS.Project.Manager
  alias PhoenixLS.Workspace.{Document, DocumentStore}

  @spec handle(TextDocumentDidOpen.t(), LSP.t()) :: {:noreply, LSP.t()}
  def handle(%TextDocumentDidOpen{params: %{text_document: text_document}}, lsp) do
    project_engine = project_engine(lsp, text_document.uri)

    :ok =
      DocumentStore.open(
        document_store(lsp, project_engine),
        text_document.uri,
        text_document.language_id,
        text_document.version,
        text_document.text
      )

    index_opened_document(lsp, project_engine, text_document)
    publish_diagnostics(lsp, project_engine, text_document.uri)

    {:noreply, lsp}
  end

  @spec handle(TextDocumentDidChange.t(), LSP.t()) :: {:noreply, LSP.t()}
  def handle(
        %TextDocumentDidChange{
          params: %{text_document: text_document, content_changes: content_changes}
        },
        lsp
      ) do
    project_engine = project_engine(lsp, text_document.uri)
    document_store = document_store(lsp, project_engine)

    case full_text_change(content_changes) do
      %{text: text} when is_binary(text) ->
        replace_document(document_store, text_document.uri, text_document.version, text)
        index_changed_document(lsp, project_engine, document_store, text_document.uri)
        publish_diagnostics(lsp, project_engine, text_document.uri)

      %{"text" => text} when is_binary(text) ->
        replace_document(document_store, text_document.uri, text_document.version, text)
        index_changed_document(lsp, project_engine, document_store, text_document.uri)
        publish_diagnostics(lsp, project_engine, text_document.uri)

      nil ->
        :ok
    end

    {:noreply, lsp}
  end

  @spec handle(TextDocumentDidClose.t(), LSP.t()) :: {:noreply, LSP.t()}
  def handle(%TextDocumentDidClose{params: %{text_document: text_document}}, lsp) do
    project_engine = project_engine(lsp, text_document.uri)

    :ok = DocumentStore.close(document_store(lsp, project_engine), text_document.uri)
    delete_indexed_document(lsp, project_engine, text_document.uri)
    Diagnostics.clear(lsp, text_document.uri)

    {:noreply, lsp}
  end

  defp replace_document(document_store, uri, version, text) do
    case DocumentStore.replace(document_store, uri, version, text) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end

  defp full_text_change(content_changes) do
    content_changes
    |> Enum.reverse()
    |> Enum.find(fn
      %{range: _range} -> false
      %{"range" => _range} -> false
      %{text: text} when is_binary(text) -> true
      %{"text" => text} when is_binary(text) -> true
      _change -> false
    end)
  end

  defp index_opened_document(lsp, {:ok, engine}, text_document) do
    document =
      Document.new(
        text_document.uri,
        text_document.language_id,
        text_document.version,
        text_document.text
      )

    Indexer.schedule_document(engine.indexer, document, indexer_opts(lsp, engine))
  end

  defp index_opened_document(_lsp, :error, _text_document), do: :ok

  defp index_changed_document(lsp, {:ok, engine}, document_store, uri) do
    case DocumentStore.fetch(document_store, uri) do
      {:ok, document} ->
        Indexer.schedule_document(engine.indexer, document, indexer_opts(lsp, engine))

      :error ->
        :ok
    end
  end

  defp index_changed_document(_lsp, :error, _document_store, _uri), do: :ok

  defp delete_indexed_document(lsp, {:ok, engine}, uri) do
    Indexer.delete_uri(engine.indexer, uri, indexer_opts(lsp, engine))
  end

  defp delete_indexed_document(_lsp, :error, _uri), do: :ok

  defp publish_diagnostics(lsp, project_engine, uri) do
    document_store = document_store(lsp, project_engine)

    Diagnostics.schedule_publish(lsp, document_store, uri, project_engine)
  end

  defp document_store(_lsp, {:ok, engine}), do: engine.document_store

  defp document_store(lsp, :error) do
    LSP.assigns(lsp).document_store
  end

  defp project_engine(lsp, uri) do
    case Map.get(LSP.assigns(lsp), :project_manager) do
      nil ->
        :error

      project_manager ->
        case Manager.ensure_project_for_uri(project_manager, uri) do
          {:ok, engine} -> {:ok, engine}
          :error -> :error
          {:error, _reason} -> :error
        end
    end
  end

  defp indexer_opts(lsp, engine) do
    [diagnostics: {lsp.pid, engine.document_store, {:ok, engine}}]
  end
end
