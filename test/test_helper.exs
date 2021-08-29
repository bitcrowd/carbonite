# SPDX-License-Identifier: Apache-2.0

Carbonite.TestRepo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Carbonite.TestRepo, :manual)

ExUnit.start()
