#!/usr/bin/env elixir

[file_path] = System.argv()
content = File.read!(file_path)
{:ok, ast} = Code.string_to_quoted(content)

IO.inspect(ast, limit: :infinity, pretty: true)
