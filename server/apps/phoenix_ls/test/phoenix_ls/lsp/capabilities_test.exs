defmodule PhoenixLS.LSP.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.TextDocumentSyncKind

  alias GenLSP.Structures.{
    CodeActionOptions,
    CompletionOptions,
    ServerCapabilities,
    SignatureHelpOptions,
    TextDocumentSyncOptions
  }

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

  test "advertises workspace folder support" do
    capabilities = Capabilities.build()

    assert capabilities.workspace.workspace_folders.supported == true
    assert capabilities.workspace.workspace_folders.change_notifications == true
  end

  test "advertises completion support" do
    capabilities = Capabilities.build()

    assert %CompletionOptions{} = completion = capabilities.completion_provider
    assert completion.trigger_characters == [".", ":"]
    assert completion.resolve_provider == true
  end

  test "advertises hover support" do
    capabilities = Capabilities.build()

    assert capabilities.hover_provider == true
  end

  test "advertises definition support" do
    capabilities = Capabilities.build()

    assert capabilities.definition_provider == true
  end

  test "advertises signature help support" do
    capabilities = Capabilities.build()

    assert %SignatureHelpOptions{} = signature_help = capabilities.signature_help_provider
    assert signature_help.trigger_characters == ["<", " ", "(", ","]
    assert signature_help.retrigger_characters == [" ", ","]
  end

  test "advertises code action support" do
    capabilities = Capabilities.build()

    assert %CodeActionOptions{} = code_actions = capabilities.code_action_provider
    assert code_actions.code_action_kinds == ["quickfix"]
  end
end
