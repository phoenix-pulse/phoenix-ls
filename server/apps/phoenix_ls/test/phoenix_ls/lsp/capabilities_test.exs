defmodule PhoenixLS.LSP.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.TextDocumentSyncKind
  alias GenLSP.Structures.{ServerCapabilities, TextDocumentSyncOptions}
  alias PhoenixLS.LSP.Capabilities

  test "returns a GenLSP server capabilities struct" do
    capabilities = Capabilities.build()

    assert %ServerCapabilities{} = capabilities
  end

  test "advertises full text document sync" do
    capabilities = Capabilities.build()

    assert %TextDocumentSyncOptions{} = sync = capabilities.text_document_sync
    assert sync.open_close == true
    assert sync.change == TextDocumentSyncKind.full()
    assert sync.will_save == nil
    assert sync.will_save_wait_until == nil
    assert sync.save == nil
  end

  test "does not advertise request handlers that are not implemented yet" do
    capabilities = Capabilities.build()

    assert capabilities.completion_provider == nil
    assert capabilities.hover_provider == nil
    assert capabilities.definition_provider == nil
  end
end
