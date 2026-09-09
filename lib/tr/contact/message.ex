defmodule Tr.Contact.Message do
  @moduledoc """
  Validation schema for a contact form submission. Nothing is persisted; the
  struct only exists to run changeset validations before an email goes out.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          name: String.t() | nil,
          email: String.t() | nil,
          message: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :name, :string
    field :email, :string
    field :message, :string
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:name, :email, :message])
    |> validate_required([:name, :email, :message])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> validate_length(:message, min: 10, max: 5000)
  end
end
