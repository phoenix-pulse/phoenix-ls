Application.put_env(:gen_lsp, :exit_on_end, false)
Code.require_file("phoenix_ls/support/lsp_config_helpers.exs", __DIR__)
Code.require_file("phoenix_ls/support/fixtures.ex", __DIR__)
ExUnit.start()
