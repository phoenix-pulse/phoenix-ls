defmodule PhoenixLS.Features.PhoenixRequests do
  @moduledoc """
  Dispatcher for Phoenix editor explorer requests.
  """

  alias PhoenixLS.Features.PhoenixRequests.{
    ColocatedAssets,
    Components,
    Controllers,
    Events,
    Hooks,
    LiveViews,
    Routes,
    Schemas,
    Templates,
    Uploads
  }

  alias PhoenixLS.Index.Snapshot

  @type method :: String.t()

  @spec handle(method(), Snapshot.t()) :: list(map()) | nil
  def handle("phoenix/listSchemas", snapshot), do: Schemas.list(snapshot)
  def handle("phoenix/listComponents", snapshot), do: Components.list(snapshot)
  def handle("phoenix/listRoutes", snapshot), do: Routes.list(snapshot)
  def handle("phoenix/listTemplates", snapshot), do: Templates.list(snapshot)
  def handle("phoenix/listEvents", snapshot), do: Events.list(snapshot)
  def handle("phoenix/listLiveView", snapshot), do: LiveViews.list(snapshot)
  def handle("phoenix/listControllers", snapshot), do: Controllers.list(snapshot)
  def handle("phoenix/listUploads", snapshot), do: Uploads.list(snapshot)
  def handle("phoenix/listHooks", snapshot), do: Hooks.list(snapshot)
  def handle("phoenix/listColocatedAssets", snapshot), do: ColocatedAssets.list(snapshot)
  def handle("phoenix/" <> _unknown, _snapshot), do: nil
end
