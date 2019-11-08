defmodule Belt.Provider.Filesystem do
  @moduledoc """
  Provider module offering support for storing files in a directory on the
  local filesystem.
  """

  use Belt.Provider
  alias Belt.Provider.Filesystem.Config
  alias Belt.Provider.Helpers

  @max_renames Belt.Config.get(__MODULE__, :max_renames)

  @typedoc """
  Options for creating an Filesystem provider.
  """
  @type filesystem_option ::
    {:directory, String.t} |
    {:base_url, String.t}

  @doc """
  Creates a new Filesystem provider configuration.

  ## Options
  - `:directory` (required) - `Path.t` - path to folder on the file system.
  - `:base_url` - `String.t` - URL under which files stored with this configuration are accessible
  """
  @spec new([filesystem_option]) :: {:ok, Belt.Provider.configuration}
  def new(opts) do
    directory = Keyword.get(opts, :directory)
    base_url = Keyword.get(opts, :base_url, :unavailable)
    if (directory),
      do: {:ok, %Config{directory: directory, base_url: base_url}},
      else: {:error, "no directory specified"}
  end

  @doc """
  Creates a new Filesystem provider configuration with default credentials.

  Any provided `options` override the default settings which are retrieved from
  the application configuration.

  ## Example
  ```
  # config.exs
  config :belt, Belt.Provider.Filesystem,
  default: [
    directory: "/foo",
    base_url: "https://example.com/"]
  ```
  """
  @spec default([filesystem_option]) ::
    {:ok, Belt.Provider.configuration} |
    {:error, term}
  def default(options \\ []) do
    with {:ok, app_conf} <- Application.fetch_env(:belt, Belt.Provider.Filesystem),
         {:ok, defaults} <- Keyword.fetch(app_conf, :default) do
         defaults
         |> Keyword.merge(options)
         |> __MODULE__.new()
    else
      _ -> {:error, :not_set}
    end
  end


  @doc """
  Implementation of the `Belt.Provider.store/3` callback.
  """
  def store(config, file_source, options) do
    with {:ok, path} <- prepare_store(config, options),
         :ok <- File.cp(file_source, path) do
      get_info(config, path_to_identifier(path, config.directory), options)
    end
  end

  @doc """
  Implementation of the `Belt.Provider.store_data/3` callback.
  """
  def store_data(config, iodata, options) do
    with {:ok, path} <- prepare_store(config, options),
         :ok <- File.write(path, iodata) do
      get_info(config, path_to_identifier(path, config.directory), options)
    end
  end

  defp path_to_identifier(path, root_dir), do: Path.relative_to(path, Path.expand(root_dir))

  defp prepare_store(config, options) do
    directory = config.directory
    scope = Keyword.get(options, :scope, "")
    key = Keyword.get(options, :key)
    overwrite = Keyword.get(options, :overwrite, :rename)
    max_renames = if overwrite == :rename,
      do: @max_renames,
      else: 0

    create_target_file(directory, scope, key,
                       overwrite: overwrite,
                       max_renames: max_renames)
  end

  defp create_target_file(directory, scope, key, options) do
    overwrite = Keyword.get(options, :overwrite) == true
    max_renames = Keyword.get(options, :max_renames, @max_renames)
    create_target_file(directory, scope, key, overwrite, 0, max_renames)
  end

  defp create_target_file(directory, scope, key, overwrite, renames, max_renames)

  defp create_target_file(directory, scope, key, overwrite, renames, max_renames)
  when renames <= max_renames do
    open_opts = if overwrite,
      do: [:write],
      else: [:write, :exclusive]
    path = build_target_path(directory, scope, key, renames)
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      {:ok, path}
    else
      {:error, :eexist}
        -> create_target_file(directory, scope, key, overwrite, renames + 1, max_renames)
      {:error, _} = error -> error
    end
  end

  defp create_target_file(_, _, _, _, _, _),
    do: {:error, "could not create target file"}


  @doc """
  Implementation of the `Belt.Provider.delete/3` callback.
  """
  def delete(config, identifier, _options) do
    path = build_target_path(config.directory, "", identifier)
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Implementation of the `Belt.Provider.delete_scope/3` callback.
  """
  def delete_scope(config, scope, _options) do
    dir = config.directory
    path = Path.join(config.directory, scope)
    with {:ok, path} <- Helpers.ensure_included(path, dir) do
      case File.rm_rf(path) do
        {:ok, _} -> :ok
        other -> other
      end
    else
      {:error, _} -> {:error, :invalid_scope}
    end
  end

  @doc """
  Implementation of the `Belt.Provider.delete_all/2` callback.
  """
  def delete_all(config, _options) do
    File.ls!(config.directory)
    |> Enum.map(&Path.join(config.directory, &1))
    |> Enum.map(&File.rm_rf/1)
    |> Enum.reduce(:ok, fn(result, _) ->
      case result do
        {:ok, _} -> :ok
        other -> other
      end
    end)
  end


  @doc """
  Implementation of the `Belt.Provider.get_info/3` callback.
  """
  def get_info(config, identifier, options) do
    path = build_target_path(config.directory, "", identifier)
    %{size: size, ctime: modified} = File.stat!(path)
    url = case config.base_url do
      :unavailable -> :unavailable
      url -> URI.merge(url, identifier) |> to_string() |> URI.encode()
    end
    hashes = case Keyword.get(options, :hashes, []) do
      [_ | _] = algs -> Belt.Hasher.hash_file(path, algs)
      _other -> []
    end

    file_info = %Belt.FileInfo{
      identifier: identifier,
      config: config,
      size: size,
      modified: modified,
      url: url,
      hashes: hashes
    }
    {:ok, file_info}
  end

  defp build_target_path(directory, scope, key, renames \\ 0) do
    [directory, scope, key]
    |> Path.join()
    |> Path.expand()
    |> Helpers.increment_path(renames)
  end


  @doc """
  Implementation of the `Belt.Provider.get_url/3` callback.
  """
  def get_url(%{base_url: base_url}, identifier, _options) when is_binary(base_url) do
    url = base_url
      |> URI.merge(identifier)
      |> URI.to_string()
    {:ok, url}
  end

  def get_url(_, _, _), do: :unavailable


  @doc """
  Implementation of the `Belt.Provider.list_files/2` callback.
  """
  def list_files(config, options) do
    directory = config.directory
    files = do_list_files([directory], [], options)
      |> Enum.map(&Path.relative_to(&1, directory))
    {:ok, files}
  end

  def do_list_files([], files, _), do: files

  def do_list_files([dir | t], files, options) do
    {new_dirs, new_files} = File.ls!(dir)
      |> Enum.map(fn(name) ->
        path = Path.join(dir, name)
        if File.dir?(path), do: {:dir, path}, else: {:file, path}
      end)
      |> Enum.reduce({[], []}, fn({type, path}, {dirs, files}) ->
        case type do
          :dir  -> {[path | dirs], files}
          :file -> {dirs, [path | files]}
          _     -> {dirs, files}
        end
      end)

    do_list_files(new_dirs ++ t, new_files ++ files, options)
  end


  @doc """
  Implementation of the Provider.test_connection/2 callback.
  """
  def test_connection(config, _options) do
    directory = config.directory
    with {:ok, %{access: :read_write}} <- File.stat(directory) do
      :ok
    else
      {:ok, _} -> {:error, :eperm}
      {:error, reason} -> {:error, reason}
    end
  end
end
