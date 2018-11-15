defmodule Vault.Auth.TokenTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  @credentials %{token: "good_credentials"}

  test "Token login with valid credentials", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/auth/token/lookup-self", fn conn ->
      assert ["good_credentials"] == Plug.Conn.get_req_header(conn, "x-vault-token")

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{data: %{id: "token", ttl: 2000}})
      )
    end)

    {:ok, client} =
      Vault.new(
        host: "http://localhost:#{bypass.port}",
        auth: Vault.Auth.Token,
        http: Vault.Http.Tesla
      )
      |> Vault.login(@credentials)

    assert Vault.token_expired?(client) == false
    assert client.token == "token"
    assert client.credentials == @credentials
  end

  test "Token login with an invalid token", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/auth/token/lookup-self", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(401, Jason.encode!(%{errors: ["Invalid Credentials"]}))
    end)

    {:error, reason} =
      Vault.new(
        host: "http://localhost:#{bypass.port}",
        auth: Vault.Auth.Token,
        http: Vault.Http.Tesla
      )
      |> Vault.login(@credentials)

    assert reason == ["Invalid Credentials"]
  end

  test "Token login with non-spec response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/auth/token/lookup-self", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(401, Jason.encode!(%{problems: ["misconfigured"]}))
    end)

    {:error, [reason | _]} =
      Vault.new(
        host: "http://localhost:#{bypass.port}",
        auth: Vault.Auth.Token,
        http: Vault.Http.Tesla
      )
      |> Vault.login(@credentials)

    assert reason =~ "Unexpected response from vault"
  end

  test "Token login with http adapter error" do
    {:error, [reason | _]} =
      Vault.new(
        host: "http://localhost",
        auth: Vault.Auth.Token,
        http: Vault.Http.Test
      )
      |> Vault.login(%{token: "error"})

    assert reason =~ "Http adapter error"
  end

  @tag :dev_server
  test "Token login against local dev server" do
    # root token has no ttl

    client =
      Vault.new(
        host: "http://localhost:8200",
        auth: Vault.Auth.UserPass,
        http: Vault.Http.Tesla
      )

    {:ok, %{token: token}} = Vault.login(client, %{username: "tester", password: "foo"})

    {:ok, client} = Vault.set_auth(client, Vault.Auth.Token) |> Vault.login(%{token: token})

    assert client.token != nil
    assert Vault.token_expired?(client) == false
  end
end