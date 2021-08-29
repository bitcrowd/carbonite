# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.TestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :carbonite,
    adapter: Ecto.Adapters.Postgres
end
