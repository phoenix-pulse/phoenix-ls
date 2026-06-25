import { describe, expect, it } from 'vitest';
import { generateMermaidDiagram } from './mermaid-generator';

describe('generateMermaidDiagram', () => {
  it('uses explicit primary and foreign key metadata from schema fields', () => {
    const diagram = generateMermaidDiagram([
      {
        name: 'App.Accounts.User',
        tableName: 'users',
        fields: [
          { name: 'uuid', type: 'binary_id', primaryKey: true },
          { name: 'company_uuid', type: 'binary_id', foreignKey: true },
          { name: 'legacy_id', type: 'string', foreignKey: false }
        ],
        associations: []
      }
    ]);

    expect(diagram).toContain('string uuid PK');
    expect(diagram).toContain('string company_uuid FK');
    expect(diagram).toContain('string legacy_id\n');
    expect(diagram).not.toContain('string legacy_id FK');
  });

  it('includes many-to-many join metadata in relationship labels', () => {
    const diagram = generateMermaidDiagram([
      {
        name: 'App.Catalog.Product',
        tableName: 'products',
        fields: [],
        associations: [
          {
            fieldName: 'tags',
            targetModule: 'App.Catalog.Tag',
            type: 'many_to_many',
            cardinality: 'many_to_many',
            joinThrough: 'products_tags'
          }
        ]
      },
      {
        name: 'App.Catalog.Tag',
        tableName: 'tags',
        fields: [],
        associations: []
      }
    ]);

    expect(diagram).toContain('products }o--o{ tags : "many to many via products_tags"');
  });
});
