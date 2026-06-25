defmodule PhoenixLS.LiveView.JSCommandsTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.LiveView.JSCommands

  @documented_command_names [
    "add_class",
    "concat",
    "dispatch",
    "exec",
    "focus",
    "focus_first",
    "hide",
    "ignore_attributes",
    "navigate",
    "patch",
    "pop_focus",
    "push",
    "push_focus",
    "remove_attribute",
    "remove_class",
    "set_attribute",
    "show",
    "toggle",
    "toggle_attribute",
    "toggle_class",
    "transition"
  ]

  test "command metadata includes documented Phoenix.LiveView.JS commands used in HEEx" do
    assert JSCommands.names() == @documented_command_names
  end

  test "transition-capable command options include blocking" do
    for command <- ["add_class", "remove_class", "toggle_class", "transition"] do
      assert "blocking" in JSCommands.option_names(command)
    end
  end
end
