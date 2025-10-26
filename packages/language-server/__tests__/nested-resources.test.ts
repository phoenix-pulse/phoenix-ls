import { describe, it, expect, beforeEach } from 'vitest';
import { RouterRegistry } from '../src/router-registry';

describe('nested resources routing', () => {
  let routerRegistry: RouterRegistry;

  beforeEach(() => {
    routerRegistry = new RouterRegistry();
  });

  it('generates correct routes for single-level nested resources', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/admin", MyAppWeb.Admin, as: :admin do
    pipe_through :browser

    resources "/users", UserController, only: [:index, :show] do
      resources "/posts", PostController
    end
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    // User routes (only index and show)
    const userIndex = routes.find(r => r.path === '/admin/users' && r.verb === 'GET' && r.action === 'index');
    expect(userIndex).toBeDefined();
    expect(userIndex?.helperBase).toBe('admin_user');
    expect(userIndex?.params).toEqual([]);

    const userShow = routes.find(r => r.path === '/admin/users/:id' && r.verb === 'GET' && r.action === 'show');
    expect(userShow).toBeDefined();
    expect(userShow?.helperBase).toBe('admin_user');
    expect(userShow?.params).toEqual(['id']);

    // Nested post routes should have user_id param
    const postIndex = routes.find(r => r.path === '/admin/users/:user_id/posts' && r.verb === 'GET' && r.action === 'index');
    expect(postIndex).toBeDefined();
    expect(postIndex?.helperBase).toBe('admin_user_post');
    expect(postIndex?.params).toEqual(['user_id']);

    const postShow = routes.find(r => r.path === '/admin/users/:user_id/posts/:id' && r.verb === 'GET' && r.action === 'show');
    expect(postShow).toBeDefined();
    expect(postShow?.helperBase).toBe('admin_user_post');
    expect(postShow?.params).toEqual(['user_id', 'id']);

    const postNew = routes.find(r => r.path === '/admin/users/:user_id/posts/new' && r.verb === 'GET' && r.action === 'new');
    expect(postNew).toBeDefined();
    expect(postNew?.helperBase).toBe('admin_user_post');
    expect(postNew?.params).toEqual(['user_id']);

    const postCreate = routes.find(r => r.path === '/admin/users/:user_id/posts' && r.verb === 'POST' && r.action === 'create');
    expect(postCreate).toBeDefined();
    expect(postCreate?.helperBase).toBe('admin_user_post');
    expect(postCreate?.params).toEqual(['user_id']);
  });

  it('generates correct routes for multi-level nested resources', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/admin", MyAppWeb.Admin, as: :admin do
    pipe_through :browser

    resources "/authors", AuthorController do
      resources "/articles", ArticleController do
        resources "/comments", CommentController, only: [:index, :show, :create]
      end
    end
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    // Author routes
    const authorIndex = routes.find(r => r.path === '/admin/authors' && r.verb === 'GET' && r.action === 'index');
    expect(authorIndex).toBeDefined();
    expect(authorIndex?.helperBase).toBe('admin_author');
    expect(authorIndex?.params).toEqual([]);

    // Article routes (nested under author)
    const articleIndex = routes.find(r => r.path === '/admin/authors/:author_id/articles' && r.verb === 'GET' && r.action === 'index');
    expect(articleIndex).toBeDefined();
    expect(articleIndex?.helperBase).toBe('admin_author_article');
    expect(articleIndex?.params).toEqual(['author_id']);

    const articleShow = routes.find(r => r.path === '/admin/authors/:author_id/articles/:id' && r.verb === 'GET' && r.action === 'show');
    expect(articleShow).toBeDefined();
    expect(articleShow?.helperBase).toBe('admin_author_article');
    expect(articleShow?.params).toEqual(['author_id', 'id']);

    // Comment routes (nested under article, which is nested under author)
    const commentIndex = routes.find(r => r.path === '/admin/authors/:author_id/articles/:article_id/comments' && r.verb === 'GET' && r.action === 'index');
    expect(commentIndex).toBeDefined();
    expect(commentIndex?.helperBase).toBe('admin_author_article_comment');
    expect(commentIndex?.params).toEqual(['author_id', 'article_id']);

    const commentShow = routes.find(r => r.path === '/admin/authors/:author_id/articles/:article_id/comments/:id' && r.verb === 'GET' && r.action === 'show');
    expect(commentShow).toBeDefined();
    expect(commentShow?.helperBase).toBe('admin_author_article_comment');
    expect(commentShow?.params).toEqual(['author_id', 'article_id', 'id']);

    const commentCreate = routes.find(r => r.path === '/admin/authors/:author_id/articles/:article_id/comments' && r.verb === 'POST' && r.action === 'create');
    expect(commentCreate).toBeDefined();
    expect(commentCreate?.helperBase).toBe('admin_author_article_comment');
    expect(commentCreate?.params).toEqual(['author_id', 'article_id']);
  });

  it('handles nested resources with custom param names', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    resources "/authors", AuthorController, param: "slug" do
      resources "/articles", ArticleController, param: "article_slug"
    end
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    // Author routes with custom param
    const authorShow = routes.find(r => r.path === '/authors/:slug' && r.verb === 'GET' && r.action === 'show');
    expect(authorShow).toBeDefined();
    expect(authorShow?.params).toEqual(['slug']);

    // Article routes with custom params from both parent and child
    const articleIndex = routes.find(r => r.path === '/authors/:slug/articles' && r.verb === 'GET' && r.action === 'index');
    expect(articleIndex).toBeDefined();
    expect(articleIndex?.params).toEqual(['slug']);

    const articleShow = routes.find(r => r.path === '/authors/:slug/articles/:article_slug' && r.verb === 'GET' && r.action === 'show');
    expect(articleShow).toBeDefined();
    expect(articleShow?.params).toEqual(['slug', 'article_slug']);
  });

  it('handles nested singleton resources', () => {
    const routerContent = `
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    resources "/users", UserController do
      resources "/profile", ProfileController, singleton: true
    end
  end
end
    `;

    routerRegistry.updateFile('/lib/my_app_web/router.ex', routerContent);
    const routes = routerRegistry.getRoutes();

    // Profile routes (singleton - no :id param, no index action)
    const profileShow = routes.find(r => r.path === '/users/:user_id/profile' && r.verb === 'GET' && r.action === 'show');
    expect(profileShow).toBeDefined();
    expect(profileShow?.params).toEqual(['user_id']);

    const profileEdit = routes.find(r => r.path === '/users/:user_id/profile/edit' && r.verb === 'GET' && r.action === 'edit');
    expect(profileEdit).toBeDefined();
    expect(profileEdit?.params).toEqual(['user_id']);

    // Singleton should NOT have index action
    const profileIndex = routes.find(r => r.path === '/users/:user_id/profile' && r.action === 'index');
    expect(profileIndex).toBeUndefined();
  });
});
