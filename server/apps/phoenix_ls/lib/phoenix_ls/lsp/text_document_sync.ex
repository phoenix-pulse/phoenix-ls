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

  alias PhoenixLS.Project.Manager
  alias PhoenixLS.Workspace.DocumentStore

  @spec handle(TextDocumentDidOpen.t(), LSP.t()) :: {:noreply, LSP.t()}
  def handle(%TextDocumentDidOpen{params: %{text_document: text_document}}, lsp) do
    :ok =
      DocumentStore.open(
        document_store(lsp, text_document.uri),
        text_document.uri,
        text_document.language_id,
        text_document.version,
        text_document.text
      )

    {:noreply, lsp}
  end

  @spec handle(TextDocumentDidChange.t(), LSP.t()) :: {:noreply, LSP.t()}
  def handle(
        %TextDocumentDidChange{
          params: %{text_document: text_document, content_changes: content_changes}
        },
        lsp
      ) do
    case full_text_change(content_changes) do
      %{text: text} when is_binary(text) ->
        replace_document(lsp, text_document.uri, text_document.version, text)

      %{"text" => text} when is_binary(text) ->
        replace_document(lsp, text_document.uri, text_document.version, text)

      nil ->
        :ok
    end

    {:noreply, lsp}
  end

  @spec handle(TextDocumentDidClose.t(), LSP.t()) :: {:noreply, LSP.t()}
  def handle(%TextDocumentDidClose{params: %{text_document: text_document}}, lsp) do
    :ok = DocumentStore.close(document_store(lsp, text_document.uri), text_document.uri)

    {:noreply, lsp}
  end

  defp replace_document(lsp, uri, version, text) do
    case DocumentStore.replace(document_store(lsp, uri), uri, version, text) do
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

  defp document_store(lsp, uri) do
    assigns = LSP.assigns(lsp)

    case project_document_store(assigns, uri) do
      {:ok, document_store} -> document_store
      :error -> assigns.document_store
    end
  end

  defp project_document_store(assigns, uri) do
    case Map.get(assigns, :project_manager) do
      nil ->
        :error

      project_manager ->
        case Manager.ensure_project_for_uri(project_manager, uri) do
          {:ok, engine} -> {:ok, engine.document_store}
          :error -> :error
          {:error, _reason} -> :error
        end
    end
  end
end
