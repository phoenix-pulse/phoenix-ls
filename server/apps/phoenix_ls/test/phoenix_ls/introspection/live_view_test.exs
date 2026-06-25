defmodule PhoenixLS.Introspection.LiveViewTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Introspection.LiveView

  @uri "file:///tmp/app/lib/app_web/live/product_live.ex"
  @provenance %{source: :test}

  test "extracts LiveView modules and literal handle_event facts" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def handle_event("select-product", %{"id" => id}, socket) do
        {:noreply, assign(socket, :selected_id, id)}
      end

      def handle_event(event, _params, socket), do: {:noreply, socket}
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    assert Enum.map(facts, & &1.id) == [
             "AppWeb.ProductLive",
             "AppWeb.ProductLive:event:select-product",
             "AppWeb.ProductLive:assign:selected_id"
           ]

    assert [live_view, event, assign] = facts

    assert live_view.kind == :live_view
    assert live_view.data == %LiveView.LiveView{module: "AppWeb.ProductLive"}

    assert event.kind == :live_event
    assert event.range.start.line == 3

    assert Map.take(Map.from_struct(event.data), [:module, :event, :type, :handler, :arity]) == %{
             module: "AppWeb.ProductLive",
             event: "select-product",
             type: :handle_event,
             handler: "handle_event/3",
             arity: 3
           }

    assert assign.kind == :assign

    assert Map.take(Map.from_struct(assign.data), [:module, :name, :source]) == %{
             module: "AppWeb.ProductLive",
             name: "selected_id",
             source: :assign
           }
  end

  test "extracts static assign facts from LiveView assign APIs" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        socket =
          socket
          |> assign(:from_pipe, true)
          |> assign_new(:current_user, fn -> nil end)
          |> update(:count, &(&1 + 1))
          |> stream(:messages, [])
          |> stream_insert(:notifications, %{id: "n1"})
          |> assign_async(:stats, fn -> {:ok, %{stats: %{}}} end)

        {:ok, assign(socket, name: "product", total: 1)}
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    assign_facts =
      facts
      |> Enum.filter(&(&1.kind == :assign))
      |> Enum.map(fn fact ->
        Map.take(Map.from_struct(fact.data), [:module, :name, :source])
      end)
      |> Enum.sort_by(& &1.name)

    assert assign_facts == [
             %{module: "AppWeb.ProductLive", name: "count", source: :update},
             %{module: "AppWeb.ProductLive", name: "current_user", source: :assign_new},
             %{module: "AppWeb.ProductLive", name: "from_pipe", source: :assign},
             %{module: "AppWeb.ProductLive", name: "messages", source: :stream},
             %{module: "AppWeb.ProductLive", name: "name", source: :assign},
             %{module: "AppWeb.ProductLive", name: "notifications", source: :stream_insert},
             %{module: "AppWeb.ProductLive", name: "stats", source: :assign_async},
             %{module: "AppWeb.ProductLive", name: "total", source: :assign}
           ]
  end

  test "extracts literal handle_event facts from guarded clauses" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def handle_event("validate", params, socket) when is_map(params) do
        {:noreply, socket}
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    assert [%{data: event}] = Enum.filter(facts, &(&1.kind == :live_event))

    assert event.event == "validate"
    assert event.type == :handle_event
    assert event.handler == "handle_event/3"
    assert event.arity == 3
  end

  test "recognizes project-style live_view use macros" do
    source = """
    defmodule AppWeb.ProductLive do
      use AppWeb, :live_view
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    assert [%{kind: :live_view, id: "AppWeb.ProductLive"}] =
             LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)
  end

  test "extracts LiveView lifecycle and message handler function facts" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket), do: {:ok, socket}
      def handle_params(_params, _uri, socket), do: {:noreply, socket}
      def handle_async(:load_stats, {:ok, stats}, socket) when is_map(stats), do: {:noreply, socket}
      def handle_call({:lookup, id}, _from, socket), do: {:reply, id, socket}
      def handle_cast(:refresh, socket), do: {:noreply, socket}
      def handle_info({:tick, id}, socket), do: {:noreply, assign(socket, :tick_id, id)}
      def render(assigns), do: ~H"<div />"
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    assert facts
           |> Enum.filter(&(&1.kind == :live_view_function))
           |> Enum.map(&{&1.id, &1.data.name, &1.data.type, &1.data.arity}) == [
             {"AppWeb.ProductLive:live_view_function:mount/3", "mount", :mount, 3},
             {"AppWeb.ProductLive:live_view_function:handle_params/3", "handle_params",
              :handle_params, 3},
             {"AppWeb.ProductLive:live_view_function:handle_async/3", "handle_async",
              :handle_async, 3},
             {"AppWeb.ProductLive:live_view_function:handle_call/3", "handle_call", :handle_call,
              3},
             {"AppWeb.ProductLive:live_view_function:handle_cast/2", "handle_cast", :handle_cast,
              2},
             {"AppWeb.ProductLive:live_view_function:handle_info/2", "handle_info", :handle_info,
              2},
             {"AppWeb.ProductLive:live_view_function:render/1", "render", :render, 1}
           ]
  end

  test "extracts async, temporary assign, hook, and message lifecycle facts" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        socket =
          socket
          |> assign_async([:stats, :chart], fn -> {:ok, %{stats: %{}, chart: %{}}} end)
          |> start_async(:load_stats, fn -> :ok end)
          |> attach_hook(:log_events, :handle_event, fn _event, _params, socket -> {:cont, socket} end)

        {:ok, socket, temporary_assigns: [messages: []]}
      end

      def handle_async(:load_stats, {:ok, _result}, socket), do: {:noreply, socket}
      def handle_info(:tick, socket), do: {:noreply, socket}
      def handle_info("topic", socket), do: {:noreply, socket}
      def handle_info({:loaded, id}, socket), do: {:noreply, assign(socket, :loaded_id, id)}
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    assert facts
           |> Enum.filter(&(&1.kind == :live_async))
           |> Enum.map(&Map.take(Map.from_struct(&1.data), [:name, :source, :handler]))
           |> Enum.sort_by(&{&1.name, &1.source}) == [
             %{name: "chart", source: :assign_async, handler: nil},
             %{name: "load_stats", source: :handle_async, handler: "handle_async/3"},
             %{name: "load_stats", source: :start_async, handler: nil},
             %{name: "stats", source: :assign_async, handler: nil}
           ]

    assert [
             %{
               module: "AppWeb.ProductLive",
               name: "messages",
               default: "[]",
               source: :temporary_assigns
             }
           ] =
             facts
             |> Enum.filter(&(&1.kind == :live_temporary_assign))
             |> Enum.map(&Map.take(Map.from_struct(&1.data), [:module, :name, :default, :source]))

    assert [
             %{
               module: "AppWeb.ProductLive",
               name: "log_events",
               stage: :handle_event
             }
           ] =
             facts
             |> Enum.filter(&(&1.kind == :live_lifecycle_hook))
             |> Enum.map(&Map.take(Map.from_struct(&1.data), [:module, :name, :stage]))

    assert facts
           |> Enum.filter(&(&1.kind == :live_message))
           |> Enum.map(&Map.take(Map.from_struct(&1.data), [:name, :pattern, :handler]))
           |> Enum.sort_by(& &1.name) == [
             %{name: "loaded", pattern: "{:loaded, id}", handler: "handle_info/2"},
             %{name: "tick", pattern: ":tick", handler: "handle_info/2"},
             %{name: "topic", pattern: ~s("topic"), handler: "handle_info/2"}
           ]
  end

  test "extracts source-ranged LiveView navigation reference facts" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def handle_event("show", _params, socket) do
        {:noreply, push_patch(socket, to: ~p"/products")}
      end

      def go(socket), do: Phoenix.LiveView.push_navigate(socket, to: ~p"/admin")
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    navigation_facts = Enum.filter(facts, &(&1.kind == :live_navigation_reference))

    assert Enum.map(navigation_facts, fn fact ->
             Map.take(Map.from_struct(fact.data), [:module, :navigation, :path])
           end) == [
             %{module: "AppWeb.ProductLive", navigation: :patch, path: "/products"},
             %{module: "AppWeb.ProductLive", navigation: :navigate, path: "/admin"}
           ]

    assert [patch_fact, navigate_fact] = navigation_facts
    assert patch_fact.provenance == @provenance
    assert patch_fact.range.start.line == 4
    assert patch_fact.range.start.character == 15
    assert navigate_fact.range.start.line == 7
  end

  test "extracts dynamic and aliased LiveView navigation reference facts" do
    source = ~S"""
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView
      alias Phoenix.LiveView

      def handle_event("show", %{"id" => id}, socket) do
        {:noreply, push_patch(socket, to: ~p"/products/#{id}")}
      end

      def go(socket), do: LiveView.push_navigate(socket, to: ~p"/admin")
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    navigation_facts = Enum.filter(facts, &(&1.kind == :live_navigation_reference))

    assert Enum.map(navigation_facts, fn fact ->
             Map.take(Map.from_struct(fact.data), [:module, :navigation, :path])
           end) == [
             %{module: "AppWeb.ProductLive", navigation: :patch, path: "/products/:dynamic"},
             %{module: "AppWeb.ProductLive", navigation: :navigate, path: "/admin"}
           ]
  end

  test "extracts as-aliased LiveView navigation reference facts" do
    source = ~S"""
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView
      alias Phoenix.LiveView, as: LV

      def go(socket), do: LV.push_navigate(socket, to: ~p"/admin")
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    navigation_facts = Enum.filter(facts, &(&1.kind == :live_navigation_reference))

    assert Enum.map(navigation_facts, fn fact ->
             Map.take(Map.from_struct(fact.data), [:module, :navigation, :path])
           end) == [
             %{module: "AppWeb.ProductLive", navigation: :navigate, path: "/admin"}
           ]
  end

  test "extracts static allow_upload facts with literal options" do
    source = """
    defmodule AppWeb.ProfileLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .png), max_entries: 1)}
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProfileLive", body, @uri, @provenance)

    assert [%{kind: :upload} = upload] = Enum.filter(facts, &(&1.kind == :upload))

    assert Map.take(Map.from_struct(upload.data), [:module, :name, :options]) == %{
             module: "AppWeb.ProfileLive",
             name: "avatar",
             options: [accept: [".jpg", ".png"], max_entries: 1]
           }

    assert upload.range.start.line == 4
    assert upload.range.start.character == 10
  end

  test "extracts piped static allow_upload facts" do
    source = """
    defmodule AppWeb.ProfileLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        {:ok, socket |> allow_upload(:avatar, accept: ~w(.jpg .png), max_entries: 1)}
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProfileLive", body, @uri, @provenance)

    assert [%{kind: :upload} = upload] = Enum.filter(facts, &(&1.kind == :upload))

    assert Map.take(Map.from_struct(upload.data), [:module, :name, :options]) == %{
             module: "AppWeb.ProfileLive",
             name: "avatar",
             options: [accept: [".jpg", ".png"], max_entries: 1]
           }
  end

  test "extracts static upload callback usage facts" do
    source = """
    defmodule AppWeb.ProfileLive do
      use Phoenix.LiveView

      def handle_event("save", _params, socket) do
        consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry -> {:ok, path} end)
        uploaded_entries(socket, :avatar)
        upload_errors(socket, :avatar)
        cancel_upload(socket, :avatar, "ref")
        {:noreply, socket}
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProfileLive", body, @uri, @provenance)

    assert facts
           |> Enum.filter(&(&1.kind == :upload_usage))
           |> Enum.map(&{&1.data.upload, &1.data.role, &1.data.function}) == [
             {"avatar", :consume_uploaded_entries, "consume_uploaded_entries/3"},
             {"avatar", :uploaded_entries, "uploaded_entries/2"},
             {"avatar", :upload_errors, "upload_errors/2"},
             {"avatar", :cancel_upload, "cancel_upload/3"}
           ]
  end

  test "ignores unrelated remote allow_upload calls" do
    source = """
    defmodule AppWeb.ProfileLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        {:ok, MyUploads.allow_upload(socket, :avatar, accept: ~w(.jpg .png))}
      end
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProfileLive", body, @uri, @provenance)

    assert [] = Enum.filter(facts, &(&1.kind == :upload))
  end

  test "ignores LiveView callback names with unsupported arities" do
    source = """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      def mount(socket), do: {:ok, socket}
      def handle_params(params, socket), do: {:noreply, socket}
      def handle_info(message, extra, socket), do: {:noreply, socket}
      def render(assigns, opts), do: assigns
    end
    """

    {:ok, quoted} = Code.string_to_quoted(source, columns: true, token_metadata: true)
    {:defmodule, _meta, [_module_ast, [do: body]]} = quoted

    facts = LiveView.facts_for_module_body("AppWeb.ProductLive", body, @uri, @provenance)

    assert Enum.filter(facts, &(&1.kind == :live_view_function)) == []
  end
end
