import { describe, it, expect } from 'vitest';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { validateStreams } from '../src/validators/stream-diagnostics';

describe('Stream Validation', () => {
  describe('validateStreams', () => {
    it('should not warn on valid stream usage', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<table id="users" phx-update="stream">
  <tr :for={{dom_id, user} <- @streams.users} id={dom_id}>
    <td>{user.name}</td>
    <td>{user.email}</td>
  </tr>
</table>
`
      );

      const diagnostics = validateStreams(document);

      expect(diagnostics).toHaveLength(0);
    });

    it('should error on missing tuple destructuring', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<table phx-update="stream">
  <tr :for={user <- @streams.users} id={user.id}>
    <td>{user.name}</td>
  </tr>
</table>
`
      );

      const diagnostics = validateStreams(document);

      expect(diagnostics.length).toBeGreaterThan(0);
      const tupleError = diagnostics.find(d => d.code === 'stream-invalid-pattern');
      expect(tupleError).toBeDefined();
      expect(tupleError?.message).toContain('{dom_id, user}');
    });

    it('should error on missing id attribute', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<table phx-update="stream">
  <tr :for={{dom_id, user} <- @streams.users}>
    <td>{user.name}</td>
  </tr>
</table>
`
      );

      const diagnostics = validateStreams(document);

      expect(diagnostics.length).toBeGreaterThan(0);
      const idError = diagnostics.find(d => d.code === 'stream-missing-id');
      expect(idError).toBeDefined();
      expect(idError?.message).toContain('id={dom_id}');
    });

    it('should warn on missing phx-update="stream"', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<table>
  <tr :for={{dom_id, user} <- @streams.users} id={dom_id}>
    <td>{user.name}</td>
  </tr>
</table>
`
      );

      const diagnostics = validateStreams(document);

      expect(diagnostics.length).toBeGreaterThan(0);
      const phxUpdateWarning = diagnostics.find(d => d.code === 'stream-missing-phx-update');
      expect(phxUpdateWarning).toBeDefined();
      expect(phxUpdateWarning?.message).toContain('phx-update="stream"');
    });

    it('should warn when using :key with streams', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<table phx-update="stream">
  <tr :for={{dom_id, user} <- @streams.users} :key={user.id} id={dom_id}>
    <td>{user.name}</td>
  </tr>
</table>
`
      );

      const diagnostics = validateStreams(document);

      expect(diagnostics.length).toBeGreaterThan(0);
      const keyWarning = diagnostics.find(d => d.code === 'stream-unnecessary-key');
      expect(keyWarning).toBeDefined();
      expect(keyWarning?.message).toContain(':key');
      expect(keyWarning?.message).toContain('id={dom_id}');
    });

    it('should handle custom dom_id variable names', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<table phx-update="stream">
  <tr :for={{id, user} <- @streams.users}>
    <td>{user.name}</td>
  </tr>
</table>
`
      );

      const diagnostics = validateStreams(document);

      const idError = diagnostics.find(d => d.code === 'stream-missing-id');
      expect(idError).toBeDefined();
      expect(idError?.message).toContain('id={id}');
    });

    it('should handle multiple streams', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div>
  <table phx-update="stream">
    <tr :for={{dom_id, user} <- @streams.users} id={dom_id}>
      <td>{user.name}</td>
    </tr>
  </table>

  <ul phx-update="stream">
    <li :for={{dom_id, item} <- @streams.items} id={dom_id}>
      {item.title}
    </li>
  </ul>
</div>
`
      );

      const diagnostics = validateStreams(document);

      // Both should be valid
      expect(diagnostics).toHaveLength(0);
    });

    it('should handle streams with different variable names', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<table phx-update="stream">
  <tr :for={{row_id, product} <- @streams.products} id={row_id}>
    <td>{product.name}</td>
  </tr>
</table>
`
      );

      const diagnostics = validateStreams(document);

      expect(diagnostics).toHaveLength(0);
    });

    it('should not error on valid nested streams', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div phx-update="stream">
  <div :for={{dom_id, category} <- @streams.categories} id={dom_id}>
    <h2>{category.name}</h2>
    <ul phx-update="stream">
      <li :for={{item_id, item} <- @streams.items} id={item_id}>
        {item.name}
      </li>
    </ul>
  </div>
</div>
`
      );

      const diagnostics = validateStreams(document);

      // Both streams should be valid
      expect(diagnostics).toHaveLength(0);
    });

    it('should handle component tags with streams', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<.table id="users-table" phx-update="stream">
  <.row :for={{dom_id, user} <- @streams.users} id={dom_id}>
    <.cell>{user.name}</.cell>
  </.row>
</.table>
`
      );

      const diagnostics = validateStreams(document);

      expect(diagnostics).toHaveLength(0);
    });

    it('should handle self-closing tags with streams', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div phx-update="stream">
  <input :for={{dom_id, field} <- @streams.fields} id={dom_id} type="text" name={field.name} />
</div>
`
      );

      const diagnostics = validateStreams(document);

      expect(diagnostics).toHaveLength(0);
    });

    it('should not error when stream is used outside :for (valid use case)', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div>
  <p :if={Enum.empty?(@streams.users)}>
    No users yet
  </p>
  <table phx-update="stream">
    <tr :for={{dom_id, user} <- @streams.users} id={dom_id}>
      <td>{user.name}</td>
    </tr>
  </table>
</div>
`
      );

      const diagnostics = validateStreams(document);

      // Should only validate the :for usage, not the :if check
      expect(diagnostics).toHaveLength(0);
    });

    it('should handle complex expressions in :for', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<table phx-update="stream">
  <tr :for={{dom_id, user} <- @streams.users, user.active} id={dom_id}>
    <td>{user.name}</td>
  </tr>
</table>
`
      );

      const diagnostics = validateStreams(document);

      expect(diagnostics).toHaveLength(0);
    });
  });
});
