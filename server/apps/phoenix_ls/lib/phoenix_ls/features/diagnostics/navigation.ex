defmodule PhoenixLS.Features.Diagnostics.Navigation do
  @moduledoc """
  Diagnostics for LiveView patch and navigate references.
  """

  alias GenLSP.Enumerations.DiagnosticSeverity
  alias GenLSP.Structures.Diagnostic
  alias PhoenixLS.Features.{Diagnostics.Builder, Facts, TemplateFacts}
  alias PhoenixLS.HEEx.Document.{Attribute, Tag}
  alias PhoenixLS.Index.Fact
  alias PhoenixLS.LiveView.Navigation

  @spec diagnostics(String.t(), [Tag.t()], [Fact.t()]) :: [Diagnostic.t()]
  def diagnostics(uri, tags, facts)
      when is_binary(uri) and is_list(tags) and is_list(facts) do
    with {:ok, context} <- template_context(facts, uri) do
      tags
      |> Enum.flat_map(& &1.attrs)
      |> Enum.flat_map(&attribute_diagnostics(&1, context, facts))
    else
      :error -> []
    end
  end

  @spec diagnostics(String.t(), [Fact.t()]) :: [Diagnostic.t()]
  def diagnostics(uri, facts) when is_binary(uri) and is_list(facts) do
    facts
    |> Facts.by_kind(:live_navigation_reference)
    |> Enum.filter(&(&1.uri == uri))
    |> Enum.flat_map(&source_reference_diagnostics(&1, facts))
  end

  defp attribute_diagnostics(%Attribute{name: name} = attr, context, facts)
       when name in ["patch", "navigate"] do
    with {:ok, path} <- Navigation.verified_route_path(attr) do
      attr
      |> attr_reference(name, context, path)
      |> reference_diagnostics(facts)
    else
      :error -> []
    end
  end

  defp attribute_diagnostics(_attr, _module, _facts), do: []

  defp attr_reference(%Attribute{} = attr, name, context, path) do
    %{
      navigation: navigation(name),
      context: context,
      module: context.module,
      path: path,
      range: attr.value_range || attr.name_range
    }
  end

  defp source_reference_diagnostics(%Fact{} = fact, facts) do
    %{
      navigation: fact.data.navigation,
      context: %{module: fact.data.module},
      module: fact.data.module,
      path: fact.data.path,
      range: fact.range
    }
    |> reference_diagnostics(facts)
  end

  defp reference_diagnostics(
         %{navigation: navigation, module: module, path: path} = reference,
         facts
       ) do
    context = Map.get(reference, :context, %{module: module})

    case Navigation.classify(navigation, context, path, facts) do
      {:invalid_live_patch, target} ->
        [invalid_live_patch(reference, target)]

      {:invalid_live_patch_route, target} ->
        [invalid_live_route(reference, target)]

      {:invalid_live_navigate, current, target} ->
        [invalid_live_navigate(reference, current, target)]

      {:invalid_live_navigate_route, target} ->
        [invalid_live_route(reference, target)]

      {:missing_handle_params, _target} ->
        [missing_handle_params(reference)]

      :ok ->
        []

      :unknown ->
        []
    end
  end

  defp invalid_live_patch(reference, %Fact{} = target) do
    Builder.diagnostic(
      reference.range,
      "phoenix.invalid_live_patch",
      ~s(Patch navigation to "#{reference.path}" targets #{target.data.plug}.),
      %{
        "kind" => "invalid_live_patch",
        "navigation" => "patch",
        "path" => reference.path,
        "currentModule" => reference.module,
        "targetModule" => target.data.plug
      },
      DiagnosticSeverity.warning()
    )
  end

  defp invalid_live_route(reference, %Fact{} = target) do
    Builder.diagnostic(
      reference.range,
      code(reference.navigation),
      ~s(#{navigation_phrase(reference.navigation)} to "#{reference.path}" targets non-LiveView route #{route_verb(target)} #{target.data.path}.),
      %{
        "kind" => code_kind(reference.navigation),
        "navigation" => Atom.to_string(reference.navigation),
        "path" => reference.path,
        "currentModule" => reference.module,
        "targetKind" => "route",
        "targetVerb" => Navigation.route_verb_name(target),
        "targetModule" => target.data.plug
      },
      DiagnosticSeverity.warning()
    )
  end

  defp invalid_live_navigate(reference, %Fact{} = current, %Fact{} = target) do
    Builder.diagnostic(
      reference.range,
      "phoenix.invalid_live_navigate",
      ~s(Navigate to "#{reference.path}" changes live session from #{session(current)} to #{session(target)}.),
      %{
        "kind" => "invalid_live_navigate",
        "navigation" => "navigate",
        "path" => reference.path,
        "currentModule" => reference.module,
        "targetModule" => target.data.plug,
        "currentLiveSession" => current.data.live_session,
        "targetLiveSession" => target.data.live_session
      },
      DiagnosticSeverity.warning()
    )
  end

  defp missing_handle_params(reference) do
    Builder.diagnostic(
      reference.range,
      "phoenix.missing_handle_params",
      "Patch navigation for #{reference.module} requires handle_params/3.",
      %{
        "kind" => "missing_handle_params",
        "navigation" => "patch",
        "path" => reference.path,
        "module" => reference.module,
        "callback" => "handle_params/3"
      },
      DiagnosticSeverity.warning()
    )
  end

  defp session(%Fact{data: %{live_session: session}}) when is_binary(session), do: session
  defp session(_fact), do: "default"

  defp navigation("patch"), do: :patch
  defp navigation("navigate"), do: :navigate

  defp template_context(facts, uri) do
    with true <- TemplateFacts.live_view_template?(facts, uri),
         {:ok, module} <- TemplateFacts.module_for_uri(facts, uri) do
      case TemplateFacts.action_for_uri(facts, uri) do
        {:ok, action} -> {:ok, %{module: module, action: action}}
        :error -> {:ok, %{module: module}}
      end
    else
      _not_live_view_template -> :error
    end
  end

  defp code(:patch), do: "phoenix.invalid_live_patch"
  defp code(:navigate), do: "phoenix.invalid_live_navigate"

  defp code_kind(:patch), do: "invalid_live_patch"
  defp code_kind(:navigate), do: "invalid_live_navigate"

  defp navigation_phrase(:patch), do: "Patch navigation"
  defp navigation_phrase(:navigate), do: "Navigate"

  defp route_verb(%Fact{} = target) do
    target
    |> Navigation.route_verb_name()
    |> String.upcase()
  end
end
