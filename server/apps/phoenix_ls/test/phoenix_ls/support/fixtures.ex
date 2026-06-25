defmodule PhoenixLS.Support.Fixtures do
  @moduledoc false

  alias PhoenixLS.Index.ElixirSource

  @component_uri "file:///tmp/app/lib/app_web/components/core_components.ex"

  def generated_core_component_facts(uri \\ @component_uri) do
    {:ok, facts} = ElixirSource.facts(uri, generated_core_components_source())
    facts
  end

  def generated_core_components_source do
    """
    defmodule AppWeb.CoreComponents do
      attr :class, :string, default: nil

      slot :inner_block, required: true
      slot :subtitle
      slot :actions

      def header(assigns) do
        ~H\"\"\"
        <header><h1>{render_slot(@inner_block)}</h1></header>
        \"\"\"
      end

      slot :item, required: true do
        attr :title, :string, required: true
      end

      def list(assigns) do
        ~H\"\"\"
        <dl><div :for={item <- @item}>{render_slot(item)}</div></dl>
        \"\"\"
      end

      attr :navigate, :any, required: true
      slot :inner_block, required: true

      def back(assigns) do
        ~H\"\"\"
        <.link navigate={@navigate}>{render_slot(@inner_block)}</.link>
        \"\"\"
      end

      attr :id, :string, required: true
      attr :show, :boolean, default: false
      slot :inner_block, required: true

      def modal(assigns) do
        ~H\"\"\"
        <div id={@id}>{render_slot(@inner_block)}</div>
        \"\"\"
      end

      attr :for, :any, required: true
      attr :as, :any, default: nil
      attr :rest, :global, include: ~w(action enctype method)
      slot :inner_block, required: true

      def simple_form(assigns) do
        ~H\"\"\"
        <.form {@rest}>{render_slot(@inner_block)}</.form>
        \"\"\"
      end

      attr :field, :any
      attr :type, :string, values: ~w(text number)
      attr :rest, :global, include: ~w(step)

      def input(assigns) do
        ~H\"\"\"
        <input {@rest} />
        \"\"\"
      end

      attr :title, :string, required: true

      def metric_card(assigns) do
        ~H\"\"\"
        <article>{@title}</article>
        \"\"\"
      end
    end
    """
  end
end
