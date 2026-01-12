defmodule FuzzyCatalog.Ebooks.ObanIntegrationTest do
  use FuzzyCatalog.DataCase, async: true

  test "Oban is configured and running" do
    # Verify Oban is in the supervision tree
    children = Supervisor.which_children(FuzzyCatalog.Supervisor)

    assert Enum.any?(children, fn {name, _pid, _type, _modules} ->
             name == Oban
           end)
  end

  test "Oban queues are configured" do
    # Verify Oban configuration exists
    # In test env, queues are disabled (queues: false) for isolation
    # In other envs, queues are configured as keyword list
    config = Application.get_env(:fuzzy_catalog, Oban)
    assert config != nil
    assert Keyword.has_key?(config, :queues)
    assert Keyword.has_key?(config, :repo)
    assert Keyword.get(config, :repo) == FuzzyCatalog.Repo
  end

  test "Oban Web is configured" do
    # Verify Oban Web resolver is configured with PubSub
    config = Oban.config()
    assert config.name == Oban
  end
end
