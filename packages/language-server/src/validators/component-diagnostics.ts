import { Diagnostic, DiagnosticSeverity, Range } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { ComponentsRegistry, PhoenixComponent } from '../components-registry';
import {
  collectComponentUsages,
  shouldIgnoreUnknownAttribute,
  createRange,
  isSlotProvided,
} from '../utils/component-usage';

/**
 * Find similar names using simple string distance
 * Returns the closest match if distance is small enough
 */
function findSimilarName(input: string, candidates: string[]): string | null {
  if (candidates.length === 0) return null;

  // Simple similarity check: find names that start with same letter or have similar length
  const similarNames = candidates.filter(candidate => {
    // Same first letter
    if (candidate[0]?.toLowerCase() === input[0]?.toLowerCase()) return true;

    // Similar length (within 2 characters)
    if (Math.abs(candidate.length - input.length) <= 2) return true;

    // Contains as substring
    if (candidate.toLowerCase().includes(input.toLowerCase()) ||
        input.toLowerCase().includes(candidate.toLowerCase())) return true;

    return false;
  });

  if (similarNames.length === 0) return null;

  // Return the most similar one (shortest edit distance approximation)
  return similarNames.sort((a, b) => {
    const aDiff = Math.abs(a.length - input.length);
    const bDiff = Math.abs(b.length - input.length);
    return aDiff - bDiff;
  })[0] || null;
}

/**
 * Validate component usage and imports in templates
 *
 * This validator checks:
 * 1. Whether components used in templates are imported in the HTML module
 * 2. Components from CoreComponents are auto-imported (no error)
 * 3. Components from other modules require explicit import
 */
export function validateComponentUsage(
  document: TextDocument,
  componentsRegistry: ComponentsRegistry,
  templatePath: string
): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const text = document.getText();
  const componentUsages = collectComponentUsages(text, templatePath);

  if (componentUsages.length === 0) {
    return diagnostics;
  }

  const htmlModuleFile = componentsRegistry.getHtmlModuleForTemplate(templatePath);
  const imports = htmlModuleFile ? componentsRegistry.parseImports(htmlModuleFile) : null;
  const componentCache = new Map<string, PhoenixComponent>();

  componentUsages.forEach((usage) => {
    const cacheKey = usage.moduleContext
      ? `${usage.moduleContext}::${usage.componentName}`
      : usage.componentName;

    let component = componentCache.get(cacheKey);
    if (!component) {
      component = componentsRegistry.resolveComponent(templatePath, usage.componentName, {
        moduleContext: usage.moduleContext,
        fileContent: text,
      });
      if (component) {
        componentCache.set(cacheKey, component);
      }
    }

    if (!component) {
      return;
    }

    // Special handling for live_component - only validate module and id
    if (usage.componentName === 'live_component') {
      const attributeNames = new Set(usage.attributes.map(attr => attr.name));
      const componentRange = createRange(document, usage.nameStart, usage.nameEnd);

      // Check for required 'module' attribute
      if (!attributeNames.has('module')) {
        diagnostics.push({
          severity: DiagnosticSeverity.Error,
          range: componentRange,
          message: `live_component requires "module" attribute.`,
          source: 'phoenix-lsp',
          code: 'live-component-missing-module',
        });
      }

      // Check for required 'id' attribute
      if (!attributeNames.has('id')) {
        diagnostics.push({
          severity: DiagnosticSeverity.Error,
          range: componentRange,
          message: `live_component requires "id" attribute.`,
          source: 'phoenix-lsp',
          code: 'live-component-missing-id',
        });
      }

      // Skip all other validation for live_component (it accepts arbitrary assigns)
      return;
    }

    if (usage.isLocal && imports) {
      const isImported = isComponentAvailable(
        component.moduleName,
        imports.importedModules,
        imports.aliasedModules
      );

      if (!isImported) {
        diagnostics.push({
          severity: DiagnosticSeverity.Error,
          range: createRange(document, usage.openTagStart, usage.nameEnd),
          message: `Component "${usage.componentName}" from "${component.moduleName}" is not imported. Add: import ${component.moduleName}`,
          source: 'phoenix-lsp',
          code: 'component-not-imported',
        });
      }
    }

    const attributeNames = new Set(usage.attributes.map(attr => attr.name));
    const componentDisplay = usage.moduleContext
      ? `${usage.moduleContext}.${usage.componentName}`
      : usage.componentName;
    const componentRange = createRange(document, usage.nameStart, usage.nameEnd);

    const requiredAttrs = component.attributes.filter(attr => attr.required);
    const missingAttrs = requiredAttrs.filter(attr => !attributeNames.has(attr.name));

    missingAttrs.forEach(attr => {
      const attrType = attr.type ? `:${attr.type}` : '';
      let message = `Component "<.${componentDisplay}>" is missing required attribute "${attr.name}"${attrType}.`;

      // Show all required attributes if multiple are missing
      if (missingAttrs.length > 1) {
        const allRequired = missingAttrs.map(a => `"${a.name}"`).join(', ');
        message += ` Missing: ${allRequired}.`;
      }

      diagnostics.push({
        severity: DiagnosticSeverity.Error,
        range: componentRange,
        message,
        source: 'phoenix-lsp',
        code: 'component-missing-attribute',
      });
    });

    const allowsGlobalAttributes = component.attributes.some(attr => attr.type === 'global');
    if (!allowsGlobalAttributes) {
      usage.attributes.forEach(attrUsage => {
        const attrName = attrUsage.name;

        if (component.attributes.some(attr => attr.name === attrName)) {
          return;
        }
        if (shouldIgnoreUnknownAttribute(attrName)) {
          return;
        }

        // Find similar attribute names for suggestions
        const availableAttrs = component.attributes.map(attr => attr.name);
        const similarAttr = findSimilarName(attrName, availableAttrs);

        let message = `Unknown attribute "${attrName}" for component "<.${componentDisplay}>".`;
        if (similarAttr) {
          message += ` Did you mean "${similarAttr}"?`;
        } else if (availableAttrs.length > 0) {
          const attrList = availableAttrs.slice(0, 5).map(a => `"${a}"`).join(', ');
          const more = availableAttrs.length > 5 ? `, and ${availableAttrs.length - 5} more` : '';
          message += ` Available: ${attrList}${more}.`;
        }

        diagnostics.push({
          severity: DiagnosticSeverity.Warning,
          range: createRange(document, attrUsage.start, attrUsage.end),
          message,
          source: 'phoenix-lsp',
          code: 'component-unknown-attribute',
        });
      });
    }

    // Validate attribute values against allowed values
    usage.attributes.forEach(attrUsage => {
      const attrName = attrUsage.name;
      const componentAttr = component.attributes.find(attr => attr.name === attrName);

      if (!componentAttr || !componentAttr.values || componentAttr.values.length === 0) {
        return; // No validation needed if no values constraint
      }

      if (!attrUsage.valueText) {
        return; // Can't validate dynamic expressions
      }

      // Extract string literal value (remove quotes and handle atoms)
      const value = extractStringLiteral(attrUsage.valueText);
      if (!value) {
        return; // Not a string literal, skip validation
      }

      if (!componentAttr.values.includes(value)) {
        const allowedValues = componentAttr.values.map(v => `"${v}"`).join(', ');
        diagnostics.push({
          severity: DiagnosticSeverity.Warning,
          range: createRange(document, attrUsage.valueStart || attrUsage.start, attrUsage.valueEnd || attrUsage.end),
          message: `Invalid value "${value}" for attribute "${attrName}". Expected one of: ${allowedValues}.`,
          source: 'phoenix-lsp',
          code: 'component-invalid-attribute-value',
        });
      }
    });

    component.slots
      .filter(slot => slot.required)
      .forEach(slot => {
        if (isSlotProvided(slot.name, usage, text)) {
          return;
        }

        const slotLabel = slot.name === 'inner_block' ? 'inner content' : `slot ":${slot.name}"`;
        diagnostics.push({
          severity: DiagnosticSeverity.Error,
          range: componentRange,
          message: `Component "${componentDisplay}" is missing required ${slotLabel}.`,
          source: 'phoenix-lsp',
          code: 'component-missing-slot',
        });
      });

    const knownSlots = new Set(component.slots.map(slot => slot.name));
    usage.slots.forEach(slotUsage => {
      if (slotUsage.name === 'inner_block') {
        return;
      }

      // Check if slot is known
      if (knownSlots.has(slotUsage.name)) {
        // Slot is known - validate its attributes
        const slotDef = component.slots.find(s => s.name === slotUsage.name);
        if (!slotDef) return;

        // Check for required slot attributes
        const slotAttrNames = new Set(slotUsage.attributes.map(attr => attr.name));
        const requiredSlotAttrs = slotDef.attributes.filter(attr => attr.required);
        const missingSlotAttrs = requiredSlotAttrs.filter(attr => !slotAttrNames.has(attr.name));

        missingSlotAttrs.forEach(attr => {
          const attrType = attr.type ? `:${attr.type}` : '';
          let message = `Slot ":${slotUsage.name}" is missing required attribute "${attr.name}"${attrType}.`;

          if (missingSlotAttrs.length > 1) {
            const allRequired = missingSlotAttrs.map(a => `"${a.name}"`).join(', ');
            message += ` Missing: ${allRequired}.`;
          }

          diagnostics.push({
            severity: DiagnosticSeverity.Error,
            range: createRange(document, slotUsage.start, slotUsage.end),
            message,
            source: 'phoenix-lsp',
            code: 'slot-missing-attribute',
          });
        });

        // Check for unknown slot attributes
        slotUsage.attributes.forEach(attrUsage => {
          const attrName = attrUsage.name;

          if (slotDef.attributes.some(attr => attr.name === attrName)) {
            return; // Known attribute
          }
          if (shouldIgnoreUnknownAttribute(attrName)) {
            return; // HTML/Phoenix attribute
          }

          // Find similar attribute names for suggestions
          const availableSlotAttrs = slotDef.attributes.map(attr => attr.name);
          const similarAttr = findSimilarName(attrName, availableSlotAttrs);

          let message = `Unknown attribute "${attrName}" for slot ":${slotUsage.name}".`;
          if (similarAttr) {
            message += ` Did you mean "${similarAttr}"?`;
          } else if (availableSlotAttrs.length > 0) {
            const attrList = availableSlotAttrs.slice(0, 5).map(a => `"${a}"`).join(', ');
            const more = availableSlotAttrs.length > 5 ? `, and ${availableSlotAttrs.length - 5} more` : '';
            message += ` Available: ${attrList}${more}.`;
          }

          diagnostics.push({
            severity: DiagnosticSeverity.Warning,
            range: createRange(document, attrUsage.start, attrUsage.end),
            message,
            source: 'phoenix-lsp',
            code: 'slot-unknown-attribute',
          });
        });

        // Validate slot attribute values against allowed values
        slotUsage.attributes.forEach(attrUsage => {
          const attrName = attrUsage.name;
          const slotAttr = slotDef.attributes.find(attr => attr.name === attrName);

          if (!slotAttr || !slotAttr.values || slotAttr.values.length === 0) {
            return; // No validation needed
          }

          if (!attrUsage.valueText) {
            return; // Can't validate dynamic expressions
          }

          // Extract string literal value (remove quotes and handle atoms)
          const value = extractStringLiteral(attrUsage.valueText);
          if (!value) {
            return; // Not a string literal, skip validation
          }

          if (!slotAttr.values.includes(value)) {
            const allowedValues = slotAttr.values.map(v => `"${v}"`).join(', ');
            diagnostics.push({
              severity: DiagnosticSeverity.Warning,
              range: createRange(document, attrUsage.valueStart || attrUsage.start, attrUsage.valueEnd || attrUsage.end),
              message: `Invalid value "${value}" for slot attribute "${attrName}". Expected one of: ${allowedValues}.`,
              source: 'phoenix-lsp',
              code: 'slot-invalid-attribute-value',
            });
          }
        });

        return; // Slot validated, skip unknown slot check
      }

      // Slot is unknown - report error with suggestions
      const availableSlots = component.slots.map(slot => slot.name).filter(name => name !== 'inner_block');
      const similarSlot = findSimilarName(slotUsage.name, availableSlots);

      let message = `Component "<.${componentDisplay}>" does not declare slot ":${slotUsage.name}".`;
      if (similarSlot) {
        message += ` Did you mean ":${similarSlot}"?`;
      } else if (availableSlots.length > 0) {
        const slotList = availableSlots.slice(0, 3).map(s => `:${s}`).join(', ');
        const more = availableSlots.length > 3 ? `, and ${availableSlots.length - 3} more` : '';
        message += ` Available slots: ${slotList}${more}.`;
      }

      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: createRange(document, slotUsage.start, slotUsage.end),
        message,
        source: 'phoenix-lsp',
        code: 'component-unknown-slot',
      });
    });
  });

  return diagnostics;
}

/**
 * Check if a component module is available in the current context
 *
 * A component is available if:
 * - It's from CoreComponents (auto-imported via `use AppWeb, :html`)
 * - It's explicitly imported
 * - It's aliased
 */
function isComponentAvailable(
  moduleName: string,
  importedModules: string[],
  aliasedModules: Map<string, string>
): boolean {
  // CoreComponents are auto-imported in Phoenix apps
  if (moduleName.includes('CoreComponents')) {
    return true;
  }

  if (moduleName === 'Phoenix.Component' || moduleName.startsWith('Phoenix.Component.')) {
    return true;
  }

  // Check explicit imports
  if (importedModules.includes(moduleName)) {
    return true;
  }

  // Check aliases
  const aliasedModulesList = Array.from(aliasedModules.values());
  if (aliasedModulesList.includes(moduleName)) {
    return true;
  }

  return false;
}

/**
 * Extract string literal value from attribute value text
 * Handles both quoted strings ("value", 'value') and atom literals (:value)
 *
 * @param text Raw attribute value text
 * @returns Extracted value or null if not a literal
 */
function extractStringLiteral(text: string): string | null {
  const trimmed = text.trim();

  // Match quoted strings: "value" or 'value'
  const quotedMatch = trimmed.match(/^["'](.*)["']$/);
  if (quotedMatch) {
    return quotedMatch[1];
  }

  // Match atom literals: :value
  const atomMatch = trimmed.match(/^:(\w+)$/);
  if (atomMatch) {
    return atomMatch[1];
  }

  return null;
}
