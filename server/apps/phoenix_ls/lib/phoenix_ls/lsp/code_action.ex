defmodule PhoenixLS.LSP.CodeAction do
  @moduledoc """
  Handles LSP code action requests.
  """

  alias GenLSP.Requests.TextDocumentCodeAction
  alias GenLSP.Structures.Diagnostic
  alias PhoenixLS.Features.CodeAction, as: CodeActionFeature
  alias PhoenixLS.Features.Policy
  alias PhoenixLS.Index.Snapshot
  alias PhoenixLS.LSP.RequestContext
  alias PhoenixLS.Workspace.DocumentStore

  @spec handle(TextDocumentCodeAction.t(), RequestContext.t()) ::
          {:reply, [GenLSP.Structures.CodeAction.t()], GenLSP.LSP.t()}
  def handle(
        %TextDocumentCodeAction{params: %{text_document: text_document, context: action_context}},
        %RequestContext{} = context
      ) do
    actions =
      with uri when is_binary(uri) <- text_document.uri,
           {:ok, engine} <- RequestContext.project_engine_for_uri(context, uri),
           {:ok, snapshot} <- RequestContext.project_snapshot_for_uri(context, uri),
           {:ok, document} <- DocumentStore.fetch(engine.document_store, uri) do
        config = RequestContext.server_config!(context)

        CodeActionFeature.actions(
          document.text,
          uri,
          allowed_diagnostics(action_context.diagnostics, config),
          Snapshot.all(snapshot)
        )
      else
        _missing_or_invalid -> []
      end

    {:reply, actions, context.lsp}
  end

  defp allowed_diagnostics(diagnostics, config) do
    Enum.filter(diagnostics, &Policy.allow?(:code_action, diagnostic_feature_kind(&1), config))
  end

  defp diagnostic_feature_kind(%Diagnostic{
         source: "PhoenixLS",
         code: "phoenix.unknown_template"
       }),
       do: :template

  defp diagnostic_feature_kind(%Diagnostic{source: "PhoenixLS", code: code})
       when code in [
              "phoenix.unknown_route",
              "phoenix.unknown_route_helper",
              "phoenix.unknown_route_helper_action",
              "phoenix.route_helper_arity_mismatch"
            ],
       do: :route

  defp diagnostic_feature_kind(%Diagnostic{source: "PhoenixLS", code: code})
       when code in [
              "phoenix.unknown_event",
              "phoenix.invalid_phx_attr_value",
              "phoenix.unknown_phx_attr"
            ],
       do: :live_view

  defp diagnostic_feature_kind(%Diagnostic{source: "PhoenixLS", code: code})
       when is_binary(code) do
    cond do
      String.starts_with?(code, "phoenix.stream_") -> :live_view
      code == "phoenix.for_missing_key" -> :live_view
      true -> :component
    end
  end

  defp diagnostic_feature_kind(_diagnostic), do: :generic_elixir
end
