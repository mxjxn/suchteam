defmodule Suchteam.Organizations do
  @moduledoc """
  The Organizations context for managing multi-tenant organizations.
  """

  import Ecto.Query, warn: false
  alias Suchteam.Repo
  alias Suchteam.Organizations.{Organization, OrganizationMember, ApiKey}

  ## Organization functions

  @doc """
  Returns the list of organizations for a user.
  """
  def list_user_organizations(user_id) do
    from(o in Organization,
      join: m in OrganizationMember,
      on: m.organization_id == o.id,
      where: m.user_id == ^user_id,
      preload: [:owner, :subscription]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single organization.
  """
  def get_organization!(id), do: Repo.get!(Organization, id)

  @doc """
  Creates an organization and adds the owner as an owner member.
  """
  def create_organization(user, attrs \\ %{}) do
    attrs = Map.put(attrs, :owner_id, user.id)

    # Generate slug if not provided
    attrs =
      if Map.has_key?(attrs, :slug) do
        attrs
      else
        Map.put(attrs, :slug, Organization.generate_slug(attrs[:name] || ""))
      end

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:organization, Organization.changeset(%Organization{}, attrs))
    |> Ecto.Multi.insert(:owner_membership, fn %{organization: org} ->
      OrganizationMember.changeset(%OrganizationMember{}, %{
        organization_id: org.id,
        user_id: user.id,
        role: "owner"
      })
    end)
    |> Ecto.Multi.insert(:subscription, fn %{organization: org} ->
      alias Suchteam.Billing.Subscription

      Subscription.changeset(%Subscription{}, %{
        organization_id: org.id,
        plan: "free",
        status: "active"
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{organization: organization}} -> {:ok, organization}
      {:error, _operation, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Updates an organization.
  """
  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an organization.
  """
  def delete_organization(%Organization{} = organization) do
    Repo.delete(organization)
  end

  ## Organization member functions

  @doc """
  Checks if a user is a member of an organization with the given role.
  """
  def member?(%Organization{id: org_id}, user_id, required_role \\ nil) do
    query =
      from m in OrganizationMember,
        where: m.organization_id == ^org_id and m.user_id == ^user_id

    query =
      if required_role do
        from m in query, where: m.role in ^role_hierarchy(required_role)
      else
        query
      end

    Repo.exists?(query)
  end

  defp role_hierarchy("owner"), do: ["owner"]
  defp role_hierarchy("admin"), do: ["owner", "admin"]
  defp role_hierarchy("member"), do: ["owner", "admin", "member"]
  defp role_hierarchy(_), do: []

  @doc """
  Adds a member to an organization.
  """
  def add_member(%Organization{} = organization, user_id, role \\ "member") do
    %OrganizationMember{}
    |> OrganizationMember.changeset(%{
      organization_id: organization.id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  ## API Key functions

  @doc """
  Lists all API keys for an organization.
  """
  def list_api_keys(organization_id) do
    from(k in ApiKey,
      where: k.organization_id == ^organization_id and is_nil(k.revoked_at),
      order_by: [desc: k.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Creates a new API key for an organization.
  """
  def create_api_key(organization_id, name) do
    {plain_key, key_hash, prefix} = ApiKey.generate_key()

    result =
      %ApiKey{}
      |> ApiKey.changeset(%{
        organization_id: organization_id,
        name: name,
        key_hash: key_hash,
        prefix: prefix
      })
      |> Repo.insert()

    case result do
      {:ok, api_key} -> {:ok, api_key, plain_key}
      error -> error
    end
  end

  @doc """
  Validates an API key and returns the associated organization.
  """
  def validate_api_key(plain_key) when is_binary(plain_key) do
    key_hash = ApiKey.hash_key(plain_key)

    query =
      from k in ApiKey,
        where: k.key_hash == ^key_hash and is_nil(k.revoked_at),
        where: is_nil(k.expires_at) or k.expires_at > ^DateTime.utc_now(),
        preload: [organization: :subscription]

    case Repo.one(query) do
      nil ->
        {:error, :invalid_key}

      api_key ->
        # Update last_used_at
        api_key
        |> Ecto.Changeset.change(last_used_at: DateTime.utc_now())
        |> Repo.update()

        {:ok, api_key.organization}
    end
  end

  @doc """
  Revokes an API key.
  """
  def revoke_api_key(api_key_id) do
    api_key = Repo.get!(ApiKey, api_key_id)

    api_key
    |> Ecto.Changeset.change(revoked_at: DateTime.utc_now())
    |> Repo.update()
  end
end
