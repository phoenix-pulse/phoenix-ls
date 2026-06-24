defmodule PhoenixLS.Support.URI do
  @moduledoc """
  Helpers for converting between LSP file URIs and local filesystem paths.
  """

  @type conversion_error ::
          :missing_uri_scheme
          | :invalid_file_uri
          | {:unsupported_uri_scheme, String.t()}
          | {:unsupported_file_uri_host, String.t()}

  @spec file_uri_to_path(String.t()) :: {:ok, String.t()} | {:error, conversion_error()}
  def file_uri_to_path(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{scheme: "file", host: host, path: path}
      when host in [nil, "", "localhost"] and is_binary(path) ->
        {:ok, path |> URI.decode() |> Path.expand()}

      %URI{scheme: "file", host: host} when is_binary(host) ->
        {:error, {:unsupported_file_uri_host, host}}

      %URI{scheme: nil} ->
        {:error, :missing_uri_scheme}

      %URI{scheme: scheme} when is_binary(scheme) ->
        {:error, {:unsupported_uri_scheme, scheme}}

      _uri ->
        {:error, :invalid_file_uri}
    end
  end

  @spec file_uri_to_path!(String.t()) :: String.t()
  def file_uri_to_path!(uri) do
    case file_uri_to_path(uri) do
      {:ok, path} -> path
      {:error, reason} -> raise ArgumentError, "invalid file URI: #{inspect(reason)}"
    end
  end

  @spec path_to_file_uri(String.t()) :: {:ok, String.t()}
  def path_to_file_uri(path) when is_binary(path) do
    {:ok, "file://" <> URI.encode(Path.expand(path), &path_char?/1)}
  end

  @spec path_to_file_uri!(String.t()) :: String.t()
  def path_to_file_uri!(path) do
    {:ok, uri} = path_to_file_uri(path)
    uri
  end

  defp path_char?(char) do
    URI.char_unreserved?(char) or
      char in [?/, ?:, ?@, ?!, ?$, ?&, ?', ?(, ?), ?*, ?+, ?,, ?;, ?=]
  end
end
