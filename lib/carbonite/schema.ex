defmodule Carbonite.Schema do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      require Carbonite.Prefix

      @schema_prefix Carbonite.Prefix.default_prefix()

      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
