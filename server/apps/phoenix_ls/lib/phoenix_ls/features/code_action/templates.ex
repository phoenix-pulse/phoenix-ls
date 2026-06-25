defmodule PhoenixLS.Features.CodeAction.Templates do
  @moduledoc """
  Quick fixes for controller render template diagnostics.
  """

  alias GenLSP.Enumerations.CodeActionKind

  alias GenLSP.Structures.{
    CodeAction,
    CreateFile,
    Diagnostic,
    Position,
    Range,
    TextEdit,
    WorkspaceEdit
  }

  alias PhoenixLS.Features.{Facts, TemplateFacts}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.Support.Positions

  @source "PhoenixLS"

  @spec actions(Diagnostic.t(), String.t(), String.t(), [Fact.t()]) :: [CodeAction.t()]
  def actions(
        %Diagnostic{source: @source, code: "phoenix.unknown_template"} = diagnostic,
        uri,
        source,
        facts
      )
      when is_binary(uri) and is_binary(source) and is_list(facts) do
    with {:ok, context} <- template_context(facts, uri, diagnostic) do
      change_template_actions(diagnostic, uri, source, facts, context) ++
        create_template_actions(diagnostic, facts, context)
    else
      _missing_context -> []
    end
  end

  def actions(_diagnostic, _uri, _source, _facts), do: []

  defp change_template_actions(diagnostic, uri, source, facts, context) do
    facts
    |> TemplateFacts.candidate_entries(uri)
    |> Enum.filter(&(&1.format == context.format))
    |> Enum.sort_by(&{&1.name, &1.uri})
    |> Enum.map(&template_fix(diagnostic, uri, source, &1))
  end

  defp create_template_actions(diagnostic, facts, context) do
    [
      create_template_file_action(diagnostic, context)
      | embedded_template_actions(diagnostic, facts, context)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp template_context(facts, uri, diagnostic) do
    case diagnostic.data do
      %{"template" => template, "format" => format, "candidateUris" => candidate_uris}
      when is_binary(template) and is_binary(format) and is_list(candidate_uris) ->
        {:ok,
         %{
           template: template,
           format: format,
           candidate_uris: Enum.filter(candidate_uris, &is_binary/1),
           render_module: render_module(facts, uri, diagnostic)
         }}

      _missing_diagnostic_data ->
        case template_reference(facts, diagnostic) do
          %Fact{data: data} ->
            {:ok,
             %{
               template: data.template,
               format: data.format,
               candidate_uris: data.candidate_uris,
               render_module: render_module(facts, uri, diagnostic)
             }}

          nil ->
            :error
        end
    end
  end

  defp template_reference(facts, diagnostic) do
    facts
    |> Facts.by_kind(:template_reference)
    |> Enum.find(&(&1.range == diagnostic.range))
    |> Kernel.||(controller_render_reference(facts, diagnostic))
  end

  defp controller_render_reference(facts, diagnostic) do
    facts
    |> Facts.by_kind(:controller_render)
    |> Enum.find(&(&1.range == diagnostic.range))
  end

  defp render_module(facts, uri, diagnostic) do
    case controller_render_reference(facts, diagnostic) do
      %Fact{data: %{module: module}} -> module
      nil -> module_for_uri(facts, uri)
    end
  end

  defp module_for_uri(facts, uri) do
    facts
    |> Enum.find(fn
      %Fact{kind: :module, uri: ^uri, id: module} when is_binary(module) -> true
      _fact -> false
    end)
    |> case do
      %Fact{id: module} -> module
      nil -> nil
    end
  end

  defp template_fix(diagnostic, uri, source, entry) do
    %CodeAction{
      title: ~s(Change template to "#{entry.filename}"),
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        changes: %{
          uri => [
            %TextEdit{
              range: diagnostic.range,
              new_text: replacement_text(source, diagnostic.range.start, entry)
            }
          ]
        }
      }
    }
  end

  defp replacement_text(source, position, entry) do
    case source_byte_at(source, position) do
      ?: -> ":" <> entry.name
      ?" -> ~s("#{entry.name}.#{entry.format}")
      ?' -> "'#{entry.name}.#{entry.format}'"
      _other -> ":" <> entry.name
    end
  end

  defp source_byte_at(source, position) do
    with {:ok, offset} <- Positions.lsp_position_to_offset(source, position),
         true <- offset < byte_size(source) do
      :binary.at(source, offset)
    else
      _invalid -> nil
    end
  end

  defp create_template_file_action(_diagnostic, %{candidate_uris: []}), do: nil

  defp create_template_file_action(diagnostic, context) do
    %CodeAction{
      title: ~s(Create template "#{context.template}.#{context.format}.heex"),
      kind: CodeActionKind.quick_fix(),
      diagnostics: [diagnostic],
      edit: %WorkspaceEdit{
        document_changes: [
          %CreateFile{
            kind: "create",
            uri: List.first(context.candidate_uris)
          }
        ]
      }
    }
  end

  defp embedded_template_actions(_diagnostic, _facts, %{render_module: nil}), do: []

  defp embedded_template_actions(diagnostic, facts, context) do
    with {:ok, html_module} <- html_module_for_controller(context.render_module),
         %Fact{uri: uri, range: range} <- module_fact(facts, html_module) do
      [
        %CodeAction{
          title: ~s(Create embedded template function "#{context.template}/1"),
          kind: CodeActionKind.quick_fix(),
          diagnostics: [diagnostic],
          edit: %WorkspaceEdit{
            changes: %{
              uri => [
                %TextEdit{
                  range: insert_before_module_end_range(range),
                  new_text: embedded_template_function(context.template)
                }
              ]
            }
          }
        }
      ]
    else
      _missing_html_module -> []
    end
  end

  defp html_module_for_controller(module) when is_binary(module) do
    if String.ends_with?(module, "Controller") do
      {:ok, String.replace_suffix(module, "Controller", "HTML")}
    else
      :error
    end
  end

  defp module_fact(facts, module) do
    Enum.find(facts, &(&1.kind == :module and &1.id == module))
  end

  defp insert_before_module_end_range(%{end: %{line: line}}) do
    position = %Position{line: line, character: 0}
    %Range{start: position, end: position}
  end

  defp embedded_template_function(template) do
    "\n  def #{template}(assigns) do\n" <>
      "    ~H\"\"\"\n" <>
      "    \n" <>
      "    \"\"\"\n" <>
      "  end\n"
  end
end
