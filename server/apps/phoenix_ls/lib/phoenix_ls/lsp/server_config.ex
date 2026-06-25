defmodule PhoenixLS.LSP.ServerConfig do
  @moduledoc """
  Runtime options passed by editor launchers to the Elixir language server.
  """

  @enforce_keys [
    :source_only?,
    :project_indexing_enabled?,
    :project_compilation_enabled?,
    :log_level
  ]
  defstruct [:source_only?, :project_indexing_enabled?, :project_compilation_enabled?, :log_level]

  @type t :: %__MODULE__{
          source_only?: boolean(),
          project_indexing_enabled?: boolean(),
          project_compilation_enabled?: boolean(),
          log_level: Logger.level()
        }

  @spec default() :: t()
  def default do
    %__MODULE__{
      source_only?: true,
      project_indexing_enabled?: true,
      project_compilation_enabled?: false,
      log_level: :info
    }
  end

  @spec from_env(map()) :: t()
  def from_env(env \\ System.get_env()) when is_map(env) do
    %__MODULE__{
      source_only?: env_bool(env, "PHOENIX_LS_SOURCE_ONLY", true),
      project_indexing_enabled?: env_bool(env, "PHOENIX_LS_INDEXING", true),
      project_compilation_enabled?: env_bool(env, "PHOENIX_LS_COMPILATION", false),
      log_level: env_log_level(env, "PHOENIX_LS_LOG_LEVEL", :info)
    }
  end

  defp env_bool(env, key, default) do
    case Map.get(env, key) do
      nil -> default
      value -> bool_value(value, default)
    end
  end

  defp bool_value(value, default) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      truthy when truthy in ["1", "true", "yes", "on"] -> true
      falsy when falsy in ["0", "false", "no", "off"] -> false
      _unknown -> default
    end
  end

  defp bool_value(value, _default) when is_boolean(value), do: value
  defp bool_value(_value, default), do: default

  defp env_log_level(env, key, default) do
    case Map.get(env, key) do
      nil -> default
      value -> log_level(value, default)
    end
  end

  defp log_level(value, default) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "debug" -> :debug
      "info" -> :info
      "warn" -> :warning
      "warning" -> :warning
      "error" -> :error
      _unknown -> default
    end
  end

  defp log_level(value, _default) when value in [:debug, :info, :warning, :error], do: value
  defp log_level(_value, default), do: default

  @spec project_manager_opts(t(), pid()) :: keyword()
  def project_manager_opts(
        %__MODULE__{
          source_only?: source_only?,
          project_indexing_enabled?: indexing_enabled?,
          project_compilation_enabled?: compilation_enabled?
        },
        status_target
      )
      when is_pid(status_target) do
    [
      status_target: status_target,
      source_only?: source_only?,
      project_indexing_enabled: indexing_enabled?,
      project_compilation_enabled: compilation_enabled?
    ]
  end
end
