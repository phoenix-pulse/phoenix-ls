import { describe, it, expect } from 'vitest';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { validateForLoopKeys } from '../src/validators/phoenix-diagnostics';

describe('For Loop Key Validation', () => {
  describe('validateForLoopKeys', () => {
    it('should warn when :for is used without :key', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div :for={item <- @items}>
  {item.name}
</div>
`
      );

      const diagnostics = validateForLoopKeys(document);

      expect(diagnostics).toHaveLength(1);
      expect(diagnostics[0].code).toBe('for-missing-key');
      expect(diagnostics[0].message).toContain('DOM tracking');
      expect(diagnostics[0].message).toContain('LiveView 1.0+');
      expect(diagnostics[0].message).toContain('LiveView 1.1+');
    });

    it('should not warn when :for has :key', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div :for={item <- @items} :key={item.id}>
  {item.name}
</div>
`
      );

      const diagnostics = validateForLoopKeys(document);

      expect(diagnostics).toHaveLength(0);
    });

    it('should NOT warn on component tags (components manage their own keys)', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<.card :for={user <- @users}>
  {user.name}
</.card>
`
      );

      const diagnostics = validateForLoopKeys(document);

      // Components are skipped - they manage their own keys internally
      expect(diagnostics).toHaveLength(0);
    });

    it('should handle pattern matching in :for', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<tr :for={{id, user} <- @users}>
  <td>{id}</td>
  <td>{user.name}</td>
</tr>
`
      );

      const diagnostics = validateForLoopKeys(document);

      expect(diagnostics).toHaveLength(1);
      expect(diagnostics[0].code).toBe('for-missing-key');
    });

    it('should handle multiple :for loops', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div :for={category <- @categories} :key={category.id}>
  <h2>{category.name}</h2>
  <ul>
    <li :for={item <- category.items}>
      {item.name}
    </li>
  </ul>
</div>
`
      );

      const diagnostics = validateForLoopKeys(document);

      // Only the inner loop is missing :key
      expect(diagnostics).toHaveLength(1);
      expect(diagnostics[0].message).toContain('li');
    });

    it('should handle :for with guards', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div :for={user <- @users, user.active}>
  {user.name}
</div>
`
      );

      const diagnostics = validateForLoopKeys(document);

      expect(diagnostics).toHaveLength(1);
      expect(diagnostics[0].code).toBe('for-missing-key');
    });

    it('should handle self-closing tags', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<input :for={field <- @fields} type="text" name={field.name} />
`
      );

      const diagnostics = validateForLoopKeys(document);

      expect(diagnostics).toHaveLength(1);
      expect(diagnostics[0].code).toBe('for-missing-key');
    });

    it('should work with Enum.with_index', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<li :for={{item, index} <- Enum.with_index(@items)}>
  {index + 1}. {item.name}
</li>
`
      );

      const diagnostics = validateForLoopKeys(document);

      expect(diagnostics).toHaveLength(1);
      expect(diagnostics[0].code).toBe('for-missing-key');
    });

    it('should handle :key with different spacing', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div :for={item <- @items}   :key={item.id}>
  {item.name}
</div>

<div :for={item <- @items}:key={item.id}>
  {item.name}
</div>
`
      );

      const diagnostics = validateForLoopKeys(document);

      // Both have :key, so no warnings
      expect(diagnostics).toHaveLength(0);
    });

    it('should handle composite keys', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div :for={item <- @items} :key={"#{item.category}_#{item.id}"}>
  {item.name}
</div>
`
      );

      const diagnostics = validateForLoopKeys(document);

      // Has :key, so no warning
      expect(diagnostics).toHaveLength(0);
    });

    // Stream-specific tests (streams use id={dom_id}, not :key)
    it('should NOT warn for stream iterations (uses id={dom_id})', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<.card :for={{dom_id, item} <- @streams.items} id={dom_id} />
`
      );

      const diagnostics = validateForLoopKeys(document);

      // Streams don't need :key - they use id={dom_id}
      expect(diagnostics).toHaveLength(0);
    });

    it('should NOT warn for stream iterations on HTML elements', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<div :for={{id, user} <- @streams.users} id={id}>
  {user.name}
</div>
`
      );

      const diagnostics = validateForLoopKeys(document);

      // Streams don't need :key
      expect(diagnostics).toHaveLength(0);
    });

    it('should NOT warn for stream iterations with custom variable names', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<.raffle_card :for={{dom_id, raffle} <- @streams.raffles} raffle={raffle} id={dom_id} />
`
      );

      const diagnostics = validateForLoopKeys(document);

      // This is the exact pattern from the user's bug report - should have no warnings
      expect(diagnostics).toHaveLength(0);
    });

    it('should NOT warn for multiple stream iterations', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<table phx-update="stream">
  <tr :for={{row_id, user} <- @streams.users} id={row_id}>
    <td>{user.name}</td>
  </tr>
</table>

<ul phx-update="stream">
  <li :for={{item_id, item} <- @streams.items} id={item_id}>
    {item.title}
  </li>
</ul>
`
      );

      const diagnostics = validateForLoopKeys(document);

      // Both are streams - no warnings
      expect(diagnostics).toHaveLength(0);
    });

    it('should warn for regular :for but NOT for stream :for in same file', () => {
      const document = TextDocument.create(
        'file:///test.heex',
        'phoenix-heex',
        1,
        `
<!-- Regular list - needs :key -->
<div :for={category <- @categories}>
  {category.name}
</div>

<!-- Stream - uses id={dom_id} -->
<div :for={{dom_id, user} <- @streams.users} id={dom_id}>
  {user.name}
</div>
`
      );

      const diagnostics = validateForLoopKeys(document);

      // Only the regular :for should warn (not the stream)
      expect(diagnostics).toHaveLength(1);
      expect(diagnostics[0].message).toContain('div');
      expect(diagnostics[0].code).toBe('for-missing-key');
    });
  });
});
