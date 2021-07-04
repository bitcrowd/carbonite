defmodule Carbonite.TestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :carbonite,
    adapter: Ecto.Adapters.Postgres
end
