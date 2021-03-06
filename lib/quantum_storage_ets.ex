defmodule QuantumStoragePersistentEts do
  @moduledoc """
  `PersistentEts` based implementation of a `Quantum.Storage`.
  """

  use GenServer

  require Logger

  alias __MODULE__.State

  @behaviour Quantum.Storage

  @doc false
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, opts)

  @doc false
  @impl GenServer
  def init(opts) do
    table_name =
      opts
      |> Keyword.fetch!(:name)
      |> Module.concat(Table)

    path =
      Application.app_dir(
        :quantum_storage_persistent_ets,
        "priv/tables/#{table_name}.tab"
      )

    File.mkdir_p!(Path.dirname(path))

    table =
      PersistentEts.new(table_name, path, [
        :named_table,
        :ordered_set,
        :protected
      ])

    {:ok, %State{table: table}}
  end

  @doc false
  @impl Quantum.Storage
  def jobs(storage_pid), do: GenServer.call(storage_pid, :jobs)

  @doc false
  @impl Quantum.Storage
  def add_job(storage_pid, job), do: GenServer.cast(storage_pid, {:add_job, job})

  @doc false
  @impl Quantum.Storage
  def delete_job(storage_pid, job_name), do: GenServer.cast(storage_pid, {:delete_job, job_name})

  @doc false
  @impl Quantum.Storage
  def update_job_state(storage_pid, job_name, state),
    do: GenServer.cast(storage_pid, {:update_job_state, job_name, state})

  @doc false
  @impl Quantum.Storage
  def last_execution_date(storage_pid), do: GenServer.call(storage_pid, :last_execution_date)

  @doc false
  @impl Quantum.Storage
  def update_last_execution_date(storage_pid, last_execution_date),
    do: GenServer.cast(storage_pid, {:update_last_execution_date, last_execution_date})

  @doc false
  @impl Quantum.Storage
  def purge(storage_pid), do: GenServer.cast(storage_pid, :purge)

  @doc false
  @impl GenServer
  def handle_cast({:add_job, job}, %State{table: table} = state) do
    :ets.insert(table, entry = {job_key(job.name), job})
    :ets.insert(table, {:init_jobs})

    Logger.debug(fn ->
      "[#{inspect(Node.self())}][#{__MODULE__}] inserting [#{inspect(entry)}] into Persistent ETS table [#{
        table
      }]"
    end)

    {:noreply, state}
  end

  def handle_cast({:delete_job, job_name}, %State{table: table} = state) do
    :ets.delete(table, job_key(job_name))

    {:noreply, state}
  end

  def handle_cast({:update_job_state, job_name, job_state}, %State{table: table} = state) do
    table
    |> :ets.lookup(job_key(job_name))
    |> Enum.map(&{elem(&1, 0), %{elem(&1, 1) | state: job_state}})
    |> Enum.each(&:ets.update_element(table, elem(&1, 0), {2, elem(&1, 1)}))

    {:noreply, state}
  end

  def handle_cast(
        {:update_last_execution_date, last_execution_date},
        %State{table: table} = state
      ) do
    :ets.insert(table, {:last_execution_date, last_execution_date})

    {:noreply, state}
  end

  def handle_cast(:purge, %State{table: table} = state) do
    :ets.delete_all_objects(table)

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_call(:jobs, _from, %State{table: table} = state) do
    {:reply,
     table
     |> :ets.lookup(:init_jobs)
     |> case do
       [{:init_jobs}] ->
         table
         |> :ets.match({{:job, :_}, :"$1"})
         |> List.flatten()

       [] ->
         :not_applicable
     end, state}
  end

  def handle_call(:last_execution_date, _from, %State{table: table} = state) do
    {:reply,
     table
     |> :ets.lookup(:last_execution_date)
     |> case do
       [] -> :unknown
       [{:last_execution_date, date} | _t] -> date
     end, state}
  end

  defp job_key(job_name) do
    {:job, job_name}
  end
end
