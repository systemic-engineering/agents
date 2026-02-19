# glue/sidecar.exs — Glue sidecar for agent devShell
#
# Started by shellHook. Connects to the glue daemon, joins the pg broadcast
# group, and forwards received events to the session event log.
#
# Required env:
#   GLUE_NODE        — glue daemon node   (e.g. "glue@Alexs-MacBook-Pro")
#   GLUE_COOKIE      — Erlang cookie
#   GLUE_WORKER      — this agent's worker id
#   GLUE_CHANNEL     — this agent's channel id
#   GLUE_EVENT_LOG   — path to append received events

glue_node = System.get_env("GLUE_NODE", "glue@Alexs-MacBook-Pro") |> String.to_atom()
event_log  = System.get_env("GLUE_EVENT_LOG", "/tmp/glue-events-#{:os.getpid()}.log")
worker  = System.get_env("GLUE_WORKER", "agent-#{:os.getpid()}")
channel = System.get_env("GLUE_CHANNEL", "channel-#{:os.getpid()}")

log = fn entry ->
  ts   = DateTime.utc_now() |> DateTime.to_iso8601()
  line = "[#{ts}] #{entry}\n"
  File.write!(event_log, line, [:append])
end

IO.puts("[glue sidecar] starting — worker=#{worker} channel=#{channel}")

case Node.connect(glue_node) do
  true    -> IO.puts("[glue sidecar] connected to #{glue_node}")
  :ignored -> IO.puts("[glue sidecar] already connected to #{glue_node}")
  false   ->
    IO.puts("[glue sidecar] WARNING: could not connect to #{glue_node} — is the daemon running?")
end

# Start local pg scope, then join the broadcast group
# (:pg scope must be running on this node even when the remote daemon owns it)
case :pg.start(:glue_agents) do
  {:ok, _}                        -> :ok
  {:error, {:already_started, _}} -> :ok
end
:pg.join(:glue_agents, :glue_agents, self())
IO.puts("[glue sidecar] joined glue_agents pg group — #{node()}")
log.("sidecar online — #{node()}")

loop = fn loop ->
  receive do
    {:glue_event, event} ->
      entry = inspect(event, pretty: false, limit: :infinity)
      log.(entry)
      IO.puts("[glue event] #{entry}")
      loop.(loop)

    other ->
      log.("unhandled: #{inspect(other)}")
      loop.(loop)
  end
end

loop.(loop)
