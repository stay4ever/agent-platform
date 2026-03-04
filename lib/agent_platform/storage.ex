defmodule AgentPlatform.Storage do
  @moduledoc """
  Storage module for Cloudflare R2 (S3-compatible).

  Bucket layout:
  - clients/{id}/knowledge/    -> Knowledge base documents
  - clients/{id}/reports/      -> Monthly performance reports
  - clients/{id}/conversations/ -> Conversation archives
  """

  require Logger

  @bucket System.get_env("R2_BUCKET") || "agent-platform"

  def put(key, content, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    request =
      ExAws.S3.put_object(@bucket, key, content, [
        {:content_type, content_type}
      ])

    case ExAws.request(request) do
      {:ok, _response} ->
        Logger.debug("Stored object: #{key}")
        :ok

      {:error, reason} ->
        Logger.error("Storage put failed for #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get(key) do
    request = ExAws.S3.get_object(@bucket, key)

    case ExAws.request(request) do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Storage get failed for #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def delete(key) do
    request = ExAws.S3.delete_object(@bucket, key)

    case ExAws.request(request) do
      {:ok, _} ->
        Logger.debug("Deleted object: #{key}")
        :ok

      {:error, reason} ->
        Logger.error("Storage delete failed for #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def list(prefix) do
    request = ExAws.S3.list_objects(@bucket, prefix: prefix)

    case ExAws.request(request) do
      {:ok, %{body: %{contents: contents}}} ->
        keys = Enum.map(contents, & &1.key)
        {:ok, keys}

      {:error, reason} ->
        Logger.error("Storage list failed for #{prefix}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def presigned_url(key, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    config = ExAws.Config.new(:s3)

    ExAws.S3.presigned_url(config, :get, @bucket, key,
      expires_in: expires_in
    )
  end

  # --- Convenience functions ---

  def store_knowledge(client_id, content) do
    key = "clients/#{client_id}/knowledge/base.json"
    put(key, Jason.encode!(content), content_type: "application/json")
  end

  def store_report(client_id, month, report_html) do
    key = "clients/#{client_id}/reports/#{month}-report.html"
    put(key, report_html, content_type: "text/html")
  end

  def store_conversation(client_id, conversation_id, data) do
    key = "clients/#{client_id}/conversations/#{conversation_id}.json"
    put(key, Jason.encode!(data), content_type: "application/json")
  end

  def get_knowledge(client_id) do
    key = "clients/#{client_id}/knowledge/base.json"

    case get(key) do
      {:ok, content} -> Jason.decode(content)
      error -> error
    end
  end
end
