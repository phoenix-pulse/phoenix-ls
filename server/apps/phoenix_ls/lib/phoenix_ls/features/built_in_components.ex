defmodule PhoenixLS.Features.BuiltInComponents do
  @moduledoc """
  Metadata for Phoenix.Component function components imported into HEEx templates.
  """

  alias PhoenixLS.Features.Completion.HTMLAttributes

  @components [
    %{
      name: "link",
      id: "Phoenix.Component.link/1",
      detail: "Phoenix.Component.link/1",
      doc:
        "Renders a link that supports LiveView navigation, patching, and regular browser navigation.",
      attrs: [
        %{
          name: "navigate",
          detail: "attr :navigate, :string",
          insert_text: ~s(navigate={${1:~p"/path"}}),
          doc: "Navigates to a LiveView."
        },
        %{
          name: "patch",
          detail: "attr :patch, :string",
          insert_text: ~s(patch={${1:~p"/path"}}),
          doc: "Patches the current LiveView."
        },
        %{
          name: "href",
          detail: "attr :href, :any",
          insert_text: ~s(href={${1:~p"/path"}}),
          doc: "Uses traditional browser navigation."
        },
        %{
          name: "replace",
          detail: "attr :replace, :boolean",
          insert_text: "replace={${1|true,false|}}",
          doc: "Replaces browser history instead of pushing a new entry."
        },
        %{
          name: "method",
          detail: "attr :method, :string",
          insert_text: ~s(method="${1|get,post,put,patch,delete|}"),
          doc: "HTTP method for href links."
        },
        %{
          name: "csrf_token",
          detail: "attr :csrf_token, :any",
          insert_text: "csrf_token={${1:true}}",
          doc: "CSRF token used for non-GET href links."
        }
      ],
      rest_tag: "a",
      rest_include: ~w(download hreflang referrerpolicy rel target type)
    },
    %{
      name: "live_component",
      id: "Phoenix.Component.live_component/1",
      detail: "Phoenix.Component.live_component/1",
      doc: "Renders a stateful LiveComponent.",
      attrs: [
        %{name: "module", detail: "attr :module, :atom", insert_text: "module={${1:Module}}"},
        %{name: "id", detail: "attr :id, :string", insert_text: ~s(id="${1:id}")}
      ],
      rest_tag: nil,
      rest_include: []
    },
    %{
      name: "form",
      id: "Phoenix.Component.form/1",
      detail: "Phoenix.Component.form/1",
      doc: "Renders a form tag from a form source.",
      attrs: [
        %{name: "for", detail: "attr :for, :any", insert_text: "for={${1:@form}}"},
        %{name: "as", detail: "attr :as, :atom", insert_text: "as={:${1:name}}"},
        %{name: "action", detail: "attr :action, :string", insert_text: ~s(action="${1:/path}")},
        %{
          name: "csrf_token",
          detail: "attr :csrf_token, :any",
          insert_text: "csrf_token={${1:true}}"
        },
        %{name: "errors", detail: "attr :errors, :list", insert_text: "errors={${1:[]}}"},
        %{
          name: "method",
          detail: "attr :method, :string",
          insert_text: ~s(method="${1|post,get,put,patch,delete|}")
        },
        %{
          name: "multipart",
          detail: "attr :multipart, :boolean",
          insert_text: "multipart={${1|true,false|}}"
        }
      ],
      rest_tag: "form",
      rest_include: ~w(autocomplete name rel enctype novalidate target)
    },
    %{
      name: "inputs_for",
      id: "Phoenix.Component.inputs_for/1",
      detail: "Phoenix.Component.inputs_for/1",
      doc: "Renders nested form inputs.",
      attrs: [
        %{name: "field", detail: "attr :field, :any", insert_text: "field={${1:@form[:field]}}"},
        %{name: "id", detail: "attr :id, :string", insert_text: ~s(id="${1:id}")},
        %{name: "as", detail: "attr :as, :atom", insert_text: "as={:${1:name}}"},
        %{name: "default", detail: "attr :default, :any", insert_text: "default={${1:nil}}"},
        %{name: "append", detail: "attr :append, :list", insert_text: "append={${1:[]}}"},
        %{name: "prepend", detail: "attr :prepend, :list", insert_text: "prepend={${1:[]}}"},
        %{
          name: "skip_hidden",
          detail: "attr :skip_hidden, :boolean",
          insert_text: "skip_hidden={${1|true,false|}}"
        },
        %{
          name: "skip_persistent_id",
          detail: "attr :skip_persistent_id, :boolean",
          insert_text: "skip_persistent_id={${1|true,false|}}"
        },
        %{name: "options", detail: "attr :options, :list", insert_text: "options={${1:[]}}"}
      ],
      rest_tag: nil,
      rest_include: []
    },
    %{
      name: "live_file_input",
      id: "Phoenix.Component.live_file_input/1",
      detail: "Phoenix.Component.live_file_input/1",
      doc: "Renders an input for LiveView uploads.",
      attrs: [
        %{
          name: "upload",
          detail: "attr :upload, :any",
          insert_text: "upload={${1:@uploads.name}}"
        },
        %{
          name: "accept",
          detail: "attr :accept, :string",
          insert_text: ~s(accept="${1:.jpg,.png}")
        }
      ],
      rest_tag: "input",
      rest_include: ~w(webkitdirectory required disabled capture form)
    }
  ]

  @spec all() :: [map()]
  def all, do: @components

  @spec component_for_tag(String.t() | nil) :: map() | nil
  def component_for_tag("." <> name), do: component(name)
  def component_for_tag(_tag), do: nil

  @spec component_for_id(String.t() | nil) :: map() | nil
  def component_for_id(id) when is_binary(id), do: Enum.find(@components, &(&1.id == id))
  def component_for_id(_id), do: nil

  @spec attr_for_tag(String.t() | nil, String.t() | nil) :: map() | nil
  def attr_for_tag(tag, prefix) do
    with %{attrs: _attrs} = component <- component_for_tag(tag) do
      Enum.find(attrs(component), &String.starts_with?(&1.name, prefix || ""))
    end
  end

  @spec attrs(map()) :: [map()]
  def attrs(component) do
    component.attrs
    |> Enum.map(&Map.put_new(&1, :insert_text_format, :snippet))
    |> Kernel.++(rest_attrs(component))
    |> uniq_by_name()
  end

  defp component(name), do: Enum.find(@components, &(&1.name == name))

  defp rest_attrs(%{rest_tag: nil}), do: []

  defp rest_attrs(component) do
    rest_names = MapSet.new(component.rest_include)

    component.rest_tag
    |> HTMLAttributes.attribute_specs_for()
    |> Enum.filter(fn spec ->
      name = HTMLAttributes.attribute_name(spec)
      MapSet.member?(rest_names, name) or global_attr?(name)
    end)
    |> Enum.map(&html_attr(&1))
  end

  defp html_attr(spec) do
    %{
      name: HTMLAttributes.attribute_name(spec),
      detail: HTMLAttributes.attribute_detail(spec),
      insert_text: HTMLAttributes.attribute_insert_text(spec),
      insert_text_format: HTMLAttributes.attribute_insert_text_format(spec)
    }
  end

  defp global_attr?(name) do
    Enum.any?(
      HTMLAttributes.global_attribute_specs(),
      &(HTMLAttributes.attribute_name(&1) == name)
    )
  end

  defp uniq_by_name(attrs) do
    attrs
    |> Enum.reduce({MapSet.new(), []}, fn attr, {seen, acc} ->
      if MapSet.member?(seen, attr.name) do
        {seen, acc}
      else
        {MapSet.put(seen, attr.name), [attr | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end
