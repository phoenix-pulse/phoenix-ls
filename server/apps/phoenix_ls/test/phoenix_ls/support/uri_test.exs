defmodule PhoenixLS.Support.URITest do
  use ExUnit.Case, async: true

  alias PhoenixLS.Support.URI, as: SupportURI

  test "converts file URIs to decoded absolute paths" do
    assert SupportURI.file_uri_to_path("file:///tmp/hello%20world/lib/page.ex") ==
             {:ok, "/tmp/hello world/lib/page.ex"}
  end

  test "accepts localhost file URIs" do
    assert SupportURI.file_uri_to_path("file://localhost/tmp/project/lib/page.ex") ==
             {:ok, "/tmp/project/lib/page.ex"}
  end

  test "rejects unsupported URI schemes" do
    assert SupportURI.file_uri_to_path("untitled:Untitled-1") ==
             {:error, {:unsupported_uri_scheme, "untitled"}}
  end

  test "converts paths to encoded file URIs" do
    assert SupportURI.path_to_file_uri("/tmp/hello world") ==
             {:ok, "file:///tmp/hello%20world"}
  end

  test "expands relative paths before converting to file URIs" do
    assert {:ok, uri} = SupportURI.path_to_file_uri("relative project")
    assert String.starts_with?(uri, "file:///")
    assert String.ends_with?(uri, "/relative%20project")
  end

  test "bang variants unwrap successful conversions" do
    assert SupportURI.file_uri_to_path!("file:///tmp/project") == "/tmp/project"
    assert SupportURI.path_to_file_uri!("/tmp/project") == "file:///tmp/project"
  end
end
