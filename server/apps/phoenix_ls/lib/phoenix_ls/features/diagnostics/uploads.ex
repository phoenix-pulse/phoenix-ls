defmodule PhoenixLS.Features.Diagnostics.Uploads do
  @moduledoc """
  Diagnostics for LiveView upload definitions and HEEx upload usage.
  """

  alias GenLSP.Enumerations.DiagnosticSeverity
  alias GenLSP.Structures.Range
  alias PhoenixLS.Features.{Diagnostics.Builder, Facts}
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.Index.Fact

  @required_form_bindings ["phx-change", "phx-submit"]

  @spec diagnostics([Tag.t()], [Fact.t()]) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(tags, facts) when is_list(tags) and is_list(facts) do
    diagnostics(nil, tags, facts)
  end

  @spec diagnostics(String.t() | nil, [Tag.t()], [Fact.t()]) :: [GenLSP.Structures.Diagnostic.t()]
  def diagnostics(uri, tags, facts)
      when (is_binary(uri) or is_nil(uri)) and is_list(tags) and is_list(facts) do
    upload_facts = Facts.by_kind(facts, :upload)
    usage_facts = upload_usage_facts(facts, uri)
    known_uploads = known_uploads_by_module(upload_facts)

    unknown_upload_diagnostics(usage_facts, known_uploads) ++
      upload_form_diagnostics(tags, usage_facts, known_uploads)
  end

  defp upload_usage_facts(facts, nil), do: Facts.by_kind(facts, :upload_usage)

  defp upload_usage_facts(facts, uri) do
    facts
    |> Facts.by_kind(:upload_usage)
    |> Enum.filter(&(&1.uri == uri))
  end

  defp unknown_upload_diagnostics(usage_facts, known_uploads) do
    usage_facts
    |> Enum.reject(&known_upload?(&1, known_uploads))
    |> Enum.map(&unknown_upload_diagnostic(&1, known_uploads))
  end

  defp unknown_upload_diagnostic(%Fact{} = fact, known_uploads) do
    module = fact.data.module
    upload = fact.data.upload
    known = module_known_uploads(known_uploads, module)

    Builder.diagnostic(
      fact.range,
      "phoenix.unknown_upload",
      ~s(Unknown LiveView upload "#{upload}"),
      %{
        "kind" => "unknown_upload",
        "module" => module,
        "upload" => upload,
        "knownUploads" => known
      }
    )
  end

  defp upload_form_diagnostics(tags, usage_facts, known_uploads) do
    usage_facts
    |> Enum.filter(&(&1.data.role == :live_file_input))
    |> Enum.filter(&known_upload?(&1, known_uploads))
    |> Enum.flat_map(&form_binding_diagnostics(&1, tags))
    |> Enum.uniq_by(fn diagnostic ->
      {diagnostic.code, diagnostic.range.start.line, diagnostic.range.start.character}
    end)
  end

  defp form_binding_diagnostics(%Fact{} = usage, tags) do
    with %Tag{} = input_tag <- live_file_input_tag(tags, usage.range),
         %Tag{} = form_tag <- containing_form(tags, input_tag) do
      @required_form_bindings
      |> Enum.reject(&has_attr?(form_tag, &1))
      |> Enum.map(&missing_binding_diagnostic(&1, form_tag, usage))
    else
      _missing_form -> []
    end
  end

  defp missing_binding_diagnostic(binding, %Tag{} = form_tag, %Fact{} = usage) do
    upload = usage.data.upload

    Builder.diagnostic(
      form_tag.name_range,
      "phoenix.upload_form_missing_#{underscore_binding(binding)}",
      "Upload form containing @uploads.#{upload} should define #{binding}.",
      %{
        "kind" => "upload_form_missing_binding",
        "binding" => binding,
        "module" => usage.data.module,
        "upload" => upload,
        "tag" => form_tag.name
      },
      DiagnosticSeverity.warning()
    )
  end

  defp live_file_input_tag(tags, %Range{} = usage_range) do
    Enum.find(tags, fn
      %Tag{name: ".live_file_input", attrs: attrs} ->
        Enum.any?(attrs, &upload_attr_range?(&1, usage_range))

      _tag ->
        false
    end)
  end

  defp upload_attr_range?(%Attribute{name: "upload", value_range: range}, usage_range) do
    range == usage_range
  end

  defp upload_attr_range?(_attr, _usage_range), do: false

  defp containing_form(tags, %Tag{} = input_tag) do
    tags
    |> Enum.filter(&form_tag?/1)
    |> Enum.filter(&contains_tag?(&1, input_tag))
    |> Enum.sort_by(&tag_span/1)
    |> List.first()
  end

  defp form_tag?(%Tag{kind: :html, name: "form"}), do: true
  defp form_tag?(%Tag{kind: :component, name: ".form"}), do: true
  defp form_tag?(_tag), do: false

  defp contains_tag?(%Tag{closing_range: %Range{} = closing_range} = form, %Tag{} = tag) do
    not after_position?(form.range.start, tag.range.start) and
      not after_position?(tag.range.end, closing_range.end)
  end

  defp contains_tag?(_form, _tag), do: false

  defp has_attr?(%Tag{attrs: attrs}, name), do: Enum.any?(attrs, &(&1.name == name))

  defp known_upload?(%Fact{} = fact, known_uploads) do
    fact.data.upload in module_known_uploads(known_uploads, fact.data.module)
  end

  defp known_uploads_by_module(upload_facts) do
    upload_facts
    |> Enum.group_by(& &1.data.module, & &1.data.name)
    |> Map.new(fn {module, names} -> {module, Enum.sort(Enum.uniq(names))} end)
  end

  defp module_known_uploads(known_uploads, module) do
    Map.get(known_uploads, module, [])
  end

  defp underscore_binding("phx-change"), do: "phx_change"
  defp underscore_binding("phx-submit"), do: "phx_submit"

  defp tag_span(%Tag{range: %Range{} = range, closing_range: %Range{} = closing_range}) do
    {
      closing_range.end.line - range.start.line,
      closing_range.end.character - range.start.character
    }
  end

  defp after_position?(left, right) do
    {left.line, left.character} > {right.line, right.character}
  end
end
