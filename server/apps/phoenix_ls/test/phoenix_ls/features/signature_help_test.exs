defmodule PhoenixLS.Features.SignatureHelpTest do
  use ExUnit.Case, async: true

  alias GenLSP.Enumerations.MarkupKind
  alias GenLSP.Structures.SignatureHelp
  alias PhoenixLS.Features.SignatureHelp, as: SignatureHelpFeature
  alias PhoenixLS.HEEx.CursorContext
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Support.Positions

  @uri "file:///tmp/app/lib/app_web/live/page_live.ex"

  test "returns component attribute signature help for local component tags" do
    {source, position} = source_and_position("<.button la| />")
    {:ok, context} = CursorContext.at(source, position)

    markdown = MarkupKind.markdown()

    assert %SignatureHelp{
             signatures: [signature],
             active_signature: 0,
             active_parameter: 0
           } = SignatureHelpFeature.signature_help(context, facts())

    assert signature.label == "<.button label kind disabled>"
    assert Enum.map(signature.parameters, & &1.label) == ["label", "kind", "disabled"]
    assert signature.documentation.kind == markdown
    assert String.contains?(signature.documentation.value, "AppWeb.CoreComponents.button/1")
    assert Enum.at(signature.parameters, 0).documentation.kind == markdown
    assert String.contains?(Enum.at(signature.parameters, 0).documentation.value, "Required")
    assert String.contains?(Enum.at(signature.parameters, 0).documentation.value, ":string")
    assert String.contains?(Enum.at(signature.parameters, 0).documentation.value, "Visible label")
  end

  test "returns component attribute signature help for remote component tags" do
    {source, position} = source_and_position("<CoreComponents.button ki| />")
    {:ok, context} = CursorContext.at(source, position)

    assert %SignatureHelp{
             signatures: [signature],
             active_signature: 0,
             active_parameter: 1
           } = SignatureHelpFeature.signature_help(context, facts())

    assert signature.label == "<CoreComponents.button label kind disabled>"
    assert Enum.map(signature.parameters, & &1.label) == ["label", "kind", "disabled"]
    assert String.contains?(Enum.at(signature.parameters, 1).documentation.value, "Optional")
    assert String.contains?(Enum.at(signature.parameters, 1).documentation.value, "default:")
    assert String.contains?(Enum.at(signature.parameters, 1).documentation.value, ":primary")
  end

  test "returns component signature help from completed tag names" do
    {source, position} = source_and_position("<.button|")
    {:ok, context} = CursorContext.at(source, position)

    assert %SignatureHelp{
             signatures: [signature],
             active_signature: 0,
             active_parameter: 0
           } = SignatureHelpFeature.signature_help(context, facts())

    assert signature.label == "<.button label kind disabled>"
    assert Enum.map(signature.parameters, & &1.label) == ["label", "kind", "disabled"]
  end

  test "keeps the current attribute active while editing its value" do
    {source, position} = source_and_position(~s(<.button kind="pri|" />))
    {:ok, context} = CursorContext.at(source, position)

    assert %SignatureHelp{
             signatures: [signature],
             active_signature: 0,
             active_parameter: 1
           } = SignatureHelpFeature.signature_help(context, facts())

    assert signature.label == "<.button label kind disabled>"
  end

  test "returns route helper signature help for Elixir calls" do
    {source, position} = source_and_position("Routes.user_path(conn, :show, |)")

    assert %SignatureHelp{
             signatures: [signature],
             active_signature: 0,
             active_parameter: 2
           } = SignatureHelpFeature.signature_help(source, position, route_facts())

    assert signature.label == "Routes.user_path(conn_or_socket, action, id)"
    assert Enum.map(signature.parameters, & &1.label) == ["conn_or_socket", "action", "id"]
    assert String.contains?(signature.documentation.value, "GET /users")
    assert String.contains?(signature.documentation.value, "GET /users/:id")
  end

  test "returns nil outside component attribute contexts" do
    {source, position} = source_and_position("<p>Hello |world</p>")
    {:ok, context} = CursorContext.at(source, position)

    assert SignatureHelpFeature.signature_help(context, facts()) == nil
  end

  defp facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.CoreComponents do
        attr :label, :string, required: true, doc: "Visible label"
        attr :kind, :atom, default: :primary
        attr :disabled, :boolean, default: false

        @doc "Renders a button."
        def button(assigns) do
          ~H\"\"\"
          <button><%= @label %></button>
          \"\"\"
        end
      end

      defmodule AppWeb.PageLive do
        alias AppWeb.CoreComponents
      end
      """)

    facts
  end

  defp route_facts do
    {:ok, facts} =
      ElixirSource.facts(@uri, """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          get "/users", UserController, :index
          get "/users/:id", UserController, :show
        end
      end
      """)

    facts
  end

  defp source_and_position(marked_source) do
    marker_offset = marker_offset!(marked_source)
    source = String.replace(marked_source, "|", "")
    {:ok, position} = Positions.offset_to_lsp_position(source, marker_offset)

    {source, position}
  end

  defp marker_offset!(marked_source) do
    marked_source
    |> :binary.matches("|")
    |> case do
      [{offset, 1}] -> offset
      [] -> raise ArgumentError, "missing cursor marker"
      _matches -> raise ArgumentError, "multiple cursor markers"
    end
  end
end
