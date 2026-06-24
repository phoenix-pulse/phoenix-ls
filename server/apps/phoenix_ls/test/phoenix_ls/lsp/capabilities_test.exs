defmodule PhoenixLS.LSP.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.TextDocumentSyncKind
  alias PhoenixLS.LSP.Capabilities

  test "advertises incremental text sync and core v2 features" do
    capabilities = Capabilities.build()

    assert capabilities.text_document_sync.open_close == true
    assert capabilities.text_document_sync.change == TextDocumentSyncKind.incremental()
    assert capabilities.completion_provider.resolve_provider == true
    assert capabilities.hover_provider == true
    assert capabilities.definition_provider == true
  end

  test "completion trigger characters include Phoenix and HEEx contexts" do
    capabilities = Capabilities.build()

    assert "<" in capabilities.completion_provider.trigger_characters
    assert "@" in capabilities.completion_provider.trigger_characters
    assert "." in capabilities.completion_provider.trigger_characters
    assert "{" in capabilities.completion_provider.trigger_characters
  end
end
