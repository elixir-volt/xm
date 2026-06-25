defmodule XM.Error do
  @moduledoc """
  Exception raised for invalid XM document, node, name, or attribute input.
  """

  defexception [:message, :reason]

  @type reason ::
          :empty_document
          | :multiple_roots
          | :invalid_name
          | :invalid_attributes
          | :invalid_text
          | :invalid_schema
          | :schema_validation_failed
          | :missing_schema

  @type t :: %__MODULE__{
          message: String.t(),
          reason: reason() | nil
        }
end
