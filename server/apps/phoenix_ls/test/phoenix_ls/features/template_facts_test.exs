defmodule PhoenixLS.Features.TemplateFactsTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Features.TemplateFacts
  alias PhoenixLS.Index.ElixirSource
  alias PhoenixLS.Introspection.Template

  test "does not infer a LiveView action unless a matching live route exists" do
    root = System.unique_integer([:positive])
    tmp_root = Path.join(System.tmp_dir!(), "phoenix-ls-template-facts-#{root}")
    live_dir = Path.join([tmp_root, "lib", "app_web", "live"])
    template_dir = Path.join(live_dir, "product_live")
    module_path = Path.join(live_dir, "product_live.ex")
    template_path = Path.join(template_dir, "admin_panel.html.heex")

    File.mkdir_p!(template_dir)

    File.write!(module_path, """
    defmodule AppWeb.ProductLive do
      use Phoenix.LiveView

      embed_templates "product_live/*"
    end
    """)

    File.write!(template_path, "<section />")

    template_uri = "file://" <> template_path

    {:ok, route_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live_session :public do
            live "/products", ProductLive, :index
          end

          live_session :admin do
            live "/admin/products", ProductLive, :admin
          end
        end
      end
      """)

    try do
      facts = route_facts ++ Template.facts(template_uri, "<section />")

      assert TemplateFacts.module_for_uri(facts, template_uri) == {:ok, "AppWeb.ProductLive"}
      assert TemplateFacts.action_for_uri(facts, template_uri) == :error
    after
      File.rm_rf!(tmp_root)
    end
  end

  test "does not infer module-stem LiveView template names as actions for acronym modules" do
    root = System.unique_integer([:positive])
    tmp_root = Path.join(System.tmp_dir!(), "phoenix-ls-template-facts-#{root}")
    live_dir = Path.join([tmp_root, "lib", "app_web", "live"])
    template_dir = Path.join(live_dir, "api_live")
    module_path = Path.join(live_dir, "api_live.ex")
    template_path = Path.join(template_dir, "api_live.html.heex")

    File.mkdir_p!(template_dir)

    File.write!(module_path, """
    defmodule AppWeb.APILive do
      use Phoenix.LiveView

      embed_templates "api_live/*"
    end
    """)

    File.write!(template_path, "<section />")

    template_uri = "file://" <> template_path

    {:ok, route_facts} =
      ElixirSource.facts("file:///tmp/app/lib/app_web/router.ex", """
      defmodule AppWeb.Router do
        use Phoenix.Router

        scope "/", AppWeb do
          live "/api", APILive, :api_live
        end
      end
      """)

    try do
      facts = route_facts ++ Template.facts(template_uri, "<section />")

      assert TemplateFacts.module_for_uri(facts, template_uri) == {:ok, "AppWeb.APILive"}
      assert TemplateFacts.action_for_uri(facts, template_uri) == :error
    after
      File.rm_rf!(tmp_root)
    end
  end
end
