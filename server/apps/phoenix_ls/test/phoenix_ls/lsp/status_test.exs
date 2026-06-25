defmodule PhoenixLS.LSP.StatusTest do
  use ExUnit.Case, async: true

  alias PhoenixLS.LSP.{Status, StatusNotification}

  test "builds indexing started payloads" do
    assert Status.indexing_started(root_uri: "file:///tmp/app", job: :project) == %{
             "kind" => "indexing",
             "phase" => "started",
             "job" => "project",
             "rootUri" => "file:///tmp/app"
           }
  end

  test "builds indexing completed payloads with result and count" do
    assert Status.indexing_completed(
             root_uri: "file:///tmp/app",
             uri: "file:///tmp/app/lib/page.ex",
             job: :document,
             result: :ok,
             count: 2
           ) == %{
             "kind" => "indexing",
             "phase" => "completed",
             "job" => "document",
             "rootUri" => "file:///tmp/app",
             "uri" => "file:///tmp/app/lib/page.ex",
             "result" => "ok",
             "count" => 2
           }
  end

  test "builds compilation started payloads" do
    assert Status.compilation_started(root_uri: "file:///tmp/app") == %{
             "kind" => "compilation",
             "phase" => "started",
             "rootUri" => "file:///tmp/app"
           }
  end

  test "builds compilation completed payloads" do
    assert Status.compilation_completed(
             root_uri: "file:///tmp/app",
             result: {:error, :timeout},
             source_only?: false
           ) == %{
             "kind" => "compilation",
             "phase" => "completed",
             "rootUri" => "file:///tmp/app",
             "result" => "error: :timeout",
             "sourceOnly" => false
           }
  end

  test "builds project degraded payloads" do
    assert Status.project_degraded("file:///tmp/app", {:exit, :missing}) == %{
             "kind" => "project",
             "state" => "degraded",
             "rootUri" => "file:///tmp/app",
             "sourceOnly" => true,
             "reason" => "{:exit, :missing}"
           }
  end

  test "status notification dumps to phoenix/status" do
    notification = %StatusNotification{params: Status.indexing_started(job: :project)}

    assert {:ok,
            %{
              "jsonrpc" => "2.0",
              "method" => "phoenix/status",
              "params" => %{
                "kind" => "indexing",
                "phase" => "started",
                "job" => "project"
              }
            }} = Schematic.dump(StatusNotification.schema(), notification)
  end
end
