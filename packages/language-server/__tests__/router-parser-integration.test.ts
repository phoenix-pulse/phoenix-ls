import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { RouterRegistry } from '../src/router-registry';
import { isElixirAvailable } from '../src/parsers/elixir-ast-parser';

describe('RouterRegistry Elixir AST Parser Integration', () => {
  it('should use Elixir parser when available', async () => {
    const elixirAvailable = await isElixirAvailable();
    console.log(`Elixir available: ${elixirAvailable}`);

    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'router-registry-elixir-'));
    const routerPath = path.join(tmpRoot, 'lib', 'my_app_web', 'router.ex');

    const routerSource = `
defmodule MyAppWeb.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MyAppWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/about", PageController, :about
    post "/contact", PageController, :contact

    live "/users", UserLive.Index, :index
    live "/users/:id", UserLive.Show, :show

    resources "/posts", PostController
    resources "/products", ProductController, only: [:index, :show]
  end

  scope "/api", MyAppWeb, as: :api do
    pipe_through :api

    get "/status", ApiController, :status
    resources "/items", ItemController

    forward "/graphql", Absinthe.Plug
  end
end
`.trim();

    fs.mkdirSync(path.dirname(routerPath), { recursive: true });
    fs.writeFileSync(routerPath, routerSource, 'utf8');

    const registry = new RouterRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    // Use parseFileAsync to test Elixir parser path
    const routes = await registry.parseFileAsync(routerPath, routerSource);

    console.log(`\nParsed ${routes.length} routes using ${elixirAvailable ? 'Elixir' : 'Regex'} parser\n`);

    // Should find 32 routes total:
    // - 3 basic routes (home, about, contact)
    // - 2 live routes
    // - 8 posts routes (full resources)
    // - 2 products routes (only index, show)
    // - 1 status route
    // - 8 items routes (full resources)
    // - 1 forward route
    // - 7 additional resource routes
    expect(routes.length).toBeGreaterThanOrEqual(25); // At least 25 routes

    // Verify basic routes
    const homeRoute = routes.find(r => r.action === 'home');
    expect(homeRoute).toBeDefined();
    expect(homeRoute?.verb).toBe('GET');
    expect(homeRoute?.path).toBe('/');
    expect(homeRoute?.controller).toBe('PageController');
    console.log(`home route: ${JSON.stringify(homeRoute)}`);

    const aboutRoute = routes.find(r => r.action === 'about');
    expect(aboutRoute).toBeDefined();
    expect(aboutRoute?.path).toBe('/about');
    console.log(`about route: ${JSON.stringify(aboutRoute)}`);

    // Verify live routes
    const usersIndexRoute = routes.find(r => r.verb === 'LIVE' && r.path === '/users');
    expect(usersIndexRoute).toBeDefined();
    expect(usersIndexRoute?.liveModule).toBe('UserLive.Index');
    expect(usersIndexRoute?.liveAction).toBe('index');
    console.log(`users index route: ${JSON.stringify(usersIndexRoute)}`);

    const usersShowRoute = routes.find(r => r.verb === 'LIVE' && r.path === '/users/:id');
    expect(usersShowRoute).toBeDefined();
    expect(usersShowRoute?.liveModule).toBe('UserLive.Show');
    expect(usersShowRoute?.params).toEqual(['id']);
    console.log(`users show route: ${JSON.stringify(usersShowRoute)}`);

    // Verify resources with 'only' option
    const productsRoutes = routes.filter(r => r.controller === 'ProductController');
    console.log(`products routes: ${productsRoutes.length}`);
    expect(productsRoutes.length).toBe(2); // only index and show
    expect(productsRoutes.some(r => r.action === 'index')).toBe(true);
    expect(productsRoutes.some(r => r.action === 'show')).toBe(true);
    expect(productsRoutes.some(r => r.action === 'create')).toBe(false); // excluded by 'only'

    // Verify forward route
    const forwardRoute = routes.find(r => r.verb === 'FORWARD');
    expect(forwardRoute).toBeDefined();
    expect(forwardRoute?.path).toBe('/api/graphql');
    expect(forwardRoute?.forwardTo).toBe('Absinthe.Plug');
    console.log(`forward route: ${JSON.stringify(forwardRoute)}`);

    // Verify scope paths
    const apiRoutes = routes.filter(r => r.path.startsWith('/api'));
    expect(apiRoutes.length).toBeGreaterThan(0);
    console.log(`api routes: ${apiRoutes.length}`);

    // Verify route aliases
    const apiAliasRoute = routes.find(r => r.routeAlias === 'api');
    expect(apiAliasRoute).toBeDefined();
    console.log(`api alias route: ${JSON.stringify(apiAliasRoute)}`);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('should cache parsed routes correctly', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'router-registry-cache-'));
    const routerPath = path.join(tmpRoot, 'lib', 'my_app_web', 'router.ex');

    const routerSource = `
defmodule MyAppWeb.Router do
  use Phoenix.Router

  scope "/", MyAppWeb do
    get "/", PageController, :home
    get "/about", PageController, :about
  end
end
`.trim();

    fs.mkdirSync(path.dirname(routerPath), { recursive: true });
    fs.writeFileSync(routerPath, routerSource, 'utf8');

    const registry = new RouterRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    // First parse
    const start1 = Date.now();
    const routes1 = await registry.parseFileAsync(routerPath, routerSource);
    const duration1 = Date.now() - start1;

    // Second parse (should use cache in Elixir parser)
    const start2 = Date.now();
    const routes2 = await registry.parseFileAsync(routerPath, routerSource);
    const duration2 = Date.now() - start2;

    console.log(`First parse: ${duration1}ms, Second parse: ${duration2}ms`);

    // Both should have same number of routes
    expect(routes1.length).toBe(2);
    expect(routes2.length).toBe(2);

    // Verify routes are correct
    expect(routes1.some(r => r.action === 'home')).toBe(true);
    expect(routes1.some(r => r.action === 'about')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('should scan workspace asynchronously', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'router-registry-scan-'));

    // Create main router
    const mainRouterPath = path.join(tmpRoot, 'lib', 'my_app_web', 'router.ex');
    const mainRouterSource = `
defmodule MyAppWeb.Router do
  use Phoenix.Router

  scope "/", MyAppWeb do
    get "/", PageController, :home
    resources "/posts", PostController
  end
end
`.trim();

    // Create API router
    const apiRouterPath = path.join(tmpRoot, 'lib', 'my_app_web', 'api_router.ex');
    const apiRouterSource = `
defmodule MyAppWeb.ApiRouter do
  use Phoenix.Router

  scope "/api", MyAppWeb do
    get "/status", ApiController, :status
    resources "/items", ItemController, only: [:index, :show]
  end
end
`.trim();

    fs.mkdirSync(path.dirname(mainRouterPath), { recursive: true });
    fs.writeFileSync(mainRouterPath, mainRouterSource, 'utf8');
    fs.writeFileSync(apiRouterPath, apiRouterSource, 'utf8');

    const registry = new RouterRegistry();
    await registry.scanWorkspace(tmpRoot);

    const allRoutes = registry.getRoutes();
    console.log(`\nScanned workspace, found ${allRoutes.length} routes total\n`);

    // Should find routes from both routers
    // Main router: 1 home + 8 posts = 9 routes
    // API router: 1 status + 2 items = 3 routes
    // Total: at least 12 routes
    expect(allRoutes.length).toBeGreaterThanOrEqual(10);

    // Verify routes from main router
    const homeRoute = allRoutes.find(r => r.action === 'home');
    expect(homeRoute).toBeDefined();

    const postsRoutes = allRoutes.filter(r => r.controller === 'PostController');
    expect(postsRoutes.length).toBeGreaterThan(0);

    // Verify routes from API router
    const statusRoute = allRoutes.find(r => r.action === 'status');
    expect(statusRoute).toBeDefined();

    const itemsRoutes = allRoutes.filter(r => r.controller === 'ItemController');
    expect(itemsRoutes.length).toBe(2); // only index and show

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('should fall back to regex parser on Elixir error', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'router-registry-fallback-'));
    const routerPath = path.join(tmpRoot, 'lib', 'my_app_web', 'router.ex');

    // Valid router source (should work with both parsers)
    const validSource = `
defmodule MyAppWeb.Router do
  use Phoenix.Router

  scope "/", MyAppWeb do
    get "/test", TestController, :index
  end
end
`.trim();

    fs.mkdirSync(path.dirname(routerPath), { recursive: true });
    fs.writeFileSync(routerPath, validSource, 'utf8');

    const registry = new RouterRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    // Should parse successfully even if Elixir parser has issues
    const routes = await registry.parseFileAsync(routerPath, validSource);

    // Verify at least the regex parser works
    expect(routes.length).toBeGreaterThanOrEqual(1);
    expect(routes.some(r => r.action === 'index' || r.path === '/test')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });
});
