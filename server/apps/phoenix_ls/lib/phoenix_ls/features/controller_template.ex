defmodule PhoenixLS.Features.ControllerTemplate do
  @moduledoc """
  Shared lookups for controller-rendered HEEx templates.
  """

  alias PhoenixLS.Features.{Facts, TemplateFacts}
  alias PhoenixLS.Index.Fact

  @type context :: %{
          template_module: String.t(),
          controller_module: String.t(),
          action: String.t()
        }

  @spec context([Fact.t()], String.t()) :: {:ok, context()} | :error
  def context(facts, uri) when is_list(facts) and is_binary(uri) do
    with {:ok, template_module} <- TemplateFacts.module_for_uri(facts, uri),
         {:ok, controller_module} <- controller_module(template_module),
         {:ok, action} <- template_action(facts, uri) do
      {:ok,
       %{
         template_module: template_module,
         controller_module: controller_module,
         action: action
       }}
    else
      _not_controller_template -> :error
    end
  end

  @spec assign_facts([Fact.t()], String.t()) :: [Fact.t()]
  def assign_facts(facts, uri) when is_list(facts) and is_binary(uri) do
    with {:ok, %{controller_module: controller_module, action: action}} <- context(facts, uri) do
      direct_assigns(facts, controller_module, action) ++ plug_assigns(facts, controller_module)
    else
      :error -> []
    end
  end

  @spec assign_fact([Fact.t()], String.t(), String.t()) :: Fact.t() | nil
  def assign_fact(facts, uri, assign) when is_list(facts) and is_binary(uri) do
    facts
    |> assign_facts(uri)
    |> Enum.find(&(&1.data.name == assign))
  end

  @spec assign_fact_with_prefix([Fact.t()], String.t(), String.t()) :: Fact.t() | nil
  def assign_fact_with_prefix(facts, uri, assign_prefix) when is_list(facts) and is_binary(uri) do
    facts
    |> assign_facts(uri)
    |> Enum.find(&String.starts_with?(&1.data.name, assign_prefix))
  end

  defp direct_assigns(facts, controller_module, action) do
    facts
    |> Facts.by_kind(:controller_assign)
    |> Enum.filter(fn fact ->
      fact.data.module == controller_module and fact.data.action == action
    end)
  end

  defp plug_assigns(facts, controller_module) do
    facts
    |> Facts.by_kind(:controller_plug_assign)
    |> Enum.filter(&(&1.data.module == controller_module))
  end

  defp controller_module(template_module) do
    cond do
      String.ends_with?(template_module, "HTML") ->
        {:ok, String.replace_suffix(template_module, "HTML", "Controller")}

      String.ends_with?(template_module, "View") ->
        {:ok, String.replace_suffix(template_module, "View", "Controller")}

      true ->
        :error
    end
  end

  defp template_action(facts, uri) do
    facts
    |> TemplateFacts.entries()
    |> Enum.find(&(&1.uri == uri))
    |> case do
      %{name: name} when is_binary(name) and name != "" -> {:ok, name}
      _missing_entry -> :error
    end
  end
end
