defmodule PhoenixLS.LSP.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias GenLSP.Structures.ServerCapabilities
  alias PhoenixLS.LSP.Capabilities

  test "returns a GenLSP server capabilities struct" do
    capabilities = Capabilities.build()

    assert %ServerCapabilities{} = capabilities
  end

  test "does not advertise handlers that are not implemented yet" do
    capabilities = Capabilities.build()

    assert capabilities.text_document_sync == nil
    assert capabilities.completion_provider == nil
    assert capabilities.hover_provider == nil
    assert capabilities.definition_provider == nil
  end
end
