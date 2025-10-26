import { describe, it, expect, beforeEach } from 'vitest';
import { RouterRegistry } from '../src/router-registry';

describe('match route support', () => {
  let routerRegistry: RouterRegistry;

  beforeEach(() => {
    routerRegistry = new RouterRegistry();
  });

  it('handles match with wildcard :*', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    match :*, "/catch-all", CatchAllController, :handle_any
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    const catchAll = routes.find(r => r.path === '/catch-all');
    expect(catchAll).toBeDefined();
    expect(catchAll?.verb).toBe('*');
    expect(catchAll?.controller).toBe('CatchAllController');
    expect(catchAll?.action).toBe('handle_any');
  });

  it('handles match with list of verbs', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    match [:get, :post], "/multi", MultiController, :handle
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    // Should generate separate routes for each verb
    const getRoute = routes.find(r => r.path === '/multi' && r.verb === 'GET');
    expect(getRoute).toBeDefined();
    expect(getRoute?.controller).toBe('MultiController');
    expect(getRoute?.action).toBe('handle');

    const postRoute = routes.find(r => r.path === '/multi' && r.verb === 'POST');
    expect(postRoute).toBeDefined();
    expect(postRoute?.controller).toBe('MultiController');
    expect(postRoute?.action).toBe('handle');

    // Should only have 2 routes for this path
    const multiRoutes = routes.filter(r => r.path === '/multi');
    expect(multiRoutes.length).toBe(2);
  });

  it('handles match with single verb', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    match :options, "/cors", CorsController, :preflight
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    const corsRoute = routes.find(r => r.path === '/cors');
    expect(corsRoute).toBeDefined();
    expect(corsRoute?.verb).toBe('OPTIONS');
    expect(corsRoute?.controller).toBe('CorsController');
    expect(corsRoute?.action).toBe('preflight');
  });

  it('handles match within scopes', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/api", MyAppWeb.API, as: :api do
    match [:get, :post, :put, :delete], "/webhook", WebhookController, :handle
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    // Should have 4 routes (one per verb)
    const webhookRoutes = routes.filter(r => r.path === '/api/webhook');
    expect(webhookRoutes.length).toBe(4);

    // Check each verb exists
    const verbs = webhookRoutes.map(r => r.verb).sort();
    expect(verbs).toEqual(['DELETE', 'GET', 'POST', 'PUT']);

    // Check helper base includes scope alias
    expect(webhookRoutes[0].helperBase).toBe('api_webhook');
  });

  it('handles match with params', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    match [:get, :delete], "/users/:id/archive", UserController, :archive
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    const getRoute = routes.find(r => r.path === '/users/:id/archive' && r.verb === 'GET');
    expect(getRoute).toBeDefined();
    expect(getRoute?.params).toEqual(['id']);

    const deleteRoute = routes.find(r => r.path === '/users/:id/archive' && r.verb === 'DELETE');
    expect(deleteRoute).toBeDefined();
    expect(deleteRoute?.params).toEqual(['id']);
  });

  it('verifies options and head verbs already work', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    options "/cors", CorsController, :preflight
    head "/health", HealthController, :check
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    const optionsRoute = routes.find(r => r.path === '/cors');
    expect(optionsRoute).toBeDefined();
    expect(optionsRoute?.verb).toBe('OPTIONS');

    const headRoute = routes.find(r => r.path === '/health');
    expect(headRoute).toBeDefined();
    expect(headRoute?.verb).toBe('HEAD');
  });
});
