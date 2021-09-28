# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :carbonite,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query, only: [from: 2]

  @spec count(module()) :: non_neg_integer()
  def count(schema) do
    schema
    |> from(select: count())
    |> one!(prefix: Carbonite.default_prefix())
  end
end
