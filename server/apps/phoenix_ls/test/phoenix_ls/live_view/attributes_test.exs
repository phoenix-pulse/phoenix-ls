defmodule PhoenixLS.LiveView.AttributesTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.LiveView.Attributes

  @documented_completion_attrs [
    "phx-click",
    "phx-click-away",
    "phx-blur",
    "phx-focus",
    "phx-window-blur",
    "phx-window-focus",
    "phx-keydown",
    "phx-keyup",
    "phx-window-keydown",
    "phx-window-keyup",
    "phx-viewport-top",
    "phx-viewport-bottom",
    "phx-change",
    "phx-submit",
    "phx-auto-recover",
    "phx-trigger-action",
    "phx-no-unused-field",
    "phx-disable-with",
    "phx-connected",
    "phx-disconnected",
    "phx-mounted",
    "phx-remove",
    "phx-update",
    "phx-hook",
    "phx-track-static",
    "phx-no-curly-interpolation",
    "phx-drop-target",
    "phx-target",
    "phx-value-",
    "phx-debounce",
    "phx-throttle"
  ]

  test "completion metadata includes current documented Phoenix LiveView phx attrs" do
    labels =
      Attributes.completion_attrs()
      |> Enum.map(fn {name, _detail, _snippet} -> name end)

    for attr <- @documented_completion_attrs do
      assert attr in labels
    end
  end

  test "known attrs include documented formatting and form attrs" do
    assert Attributes.known_attr?("phx-no-format")
    assert Attributes.known_attr?("phx-no-unused-field")
  end
end
