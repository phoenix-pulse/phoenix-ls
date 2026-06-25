defmodule PhoenixLS.HEEx.Document do
  @moduledoc """
  Parsed HEEx document structure.
  """

  defstruct tags: []

  @type t :: %__MODULE__{tags: [Tag.t()]}

  defmodule Tag do
    @moduledoc """
    Parsed HEEx tag with source ranges.
    """

    @enforce_keys [:kind, :name, :range, :name_range]
    defstruct [
      :kind,
      :name,
      :range,
      :name_range,
      :closing_range,
      :closing_name_range,
      attrs: [],
      self_closing?: false
    ]

    @type kind :: :component | :remote_component | :slot | :html

    @type t :: %__MODULE__{
            kind: kind(),
            name: String.t(),
            range: GenLSP.Structures.Range.t(),
            name_range: GenLSP.Structures.Range.t(),
            closing_range: GenLSP.Structures.Range.t() | nil,
            closing_name_range: GenLSP.Structures.Range.t() | nil,
            attrs: [PhoenixLS.HEEx.Document.Attribute.t()],
            self_closing?: boolean()
          }
  end

  defmodule Attribute do
    @moduledoc """
    Parsed HEEx attribute with source ranges.
    """

    @enforce_keys [:name, :range, :name_range, :value_kind]
    defstruct [:name, :range, :name_range, :value, :value_range, :value_kind]

    @type value_kind :: :quoted | :expression | :unquoted | :boolean

    @type t :: %__MODULE__{
            name: String.t(),
            range: GenLSP.Structures.Range.t(),
            name_range: GenLSP.Structures.Range.t(),
            value: String.t() | nil,
            value_range: GenLSP.Structures.Range.t() | nil,
            value_kind: value_kind()
          }
  end
end
