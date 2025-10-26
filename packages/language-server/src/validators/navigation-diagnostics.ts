import { Diagnostic, DiagnosticSeverity } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { ComponentsRegistry } from '../components-registry';
import {
  collectComponentUsages,
  createRange,
  ComponentUsage,
} from '../utils/component-usage';

function hasAttribute(usage: ComponentUsage, name: string): boolean {
  return usage.attributes.some(attr => attr.name === name);
}

export function validateNavigationComponents(
  document: TextDocument,
  componentsRegistry: ComponentsRegistry,
  templatePath: string
): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  const text = document.getText();
  const usages = collectComponentUsages(text, templatePath);

  if (usages.length === 0) {
    return diagnostics;
  }

  usages.forEach(usage => {
    const component = componentsRegistry.resolveComponent(templatePath, usage.componentName, {
      moduleContext: usage.moduleContext,
      fileContent: text,
    });

    if (!component) {
      return;
    }

    const fullName = usage.moduleContext
      ? `${usage.moduleContext}.${usage.componentName}`
      : usage.componentName;

    if (component.moduleName === 'Phoenix.Component') {
      if (component.name === 'link') {
        validateLinkComponent(document, usage, fullName, diagnostics);
      } else if (component.name === 'live_patch') {
        validateLivePatch(document, usage, fullName, diagnostics);
      } else if (component.name === 'live_redirect') {
        validateLiveRedirect(document, usage, fullName, diagnostics);
      } else if (component.name === 'live_component') {
        validateLiveComponentInvocation(document, usage, fullName, diagnostics);
      }
    }
  });

  return diagnostics;
}

function validateLinkComponent(
  document: TextDocument,
  usage: ComponentUsage,
  componentDisplay: string,
  diagnostics: Diagnostic[]
) {
  const hasHref = hasAttribute(usage, 'href');
  const hasNavigate = hasAttribute(usage, 'navigate');
  const hasPatch = hasAttribute(usage, 'patch');

  if (!hasHref && !hasNavigate && !hasPatch) {
    diagnostics.push({
      severity: DiagnosticSeverity.Warning,
      range: createRange(document, usage.nameStart, usage.nameEnd),
      message: `"${componentDisplay}" should define one of: \`navigate\`, \`patch\`, or \`href\`.`,
      source: 'phoenix-lsp',
      code: 'link-missing-target',
    });
  }

  if (hasPatch && hasNavigate) {
    diagnostics.push({
      severity: DiagnosticSeverity.Warning,
      range: createRange(document, usage.nameStart, usage.nameEnd),
      message: `"${componentDisplay}" should use only one of \`navigate\` or \`patch\`.`,
      source: 'phoenix-lsp',
      code: 'link-conflicting-target',
    });
  }
}

function validateLivePatch(
  document: TextDocument,
  usage: ComponentUsage,
  componentDisplay: string,
  diagnostics: Diagnostic[]
) {
  if (!hasAttribute(usage, 'patch')) {
    diagnostics.push({
      severity: DiagnosticSeverity.Error,
      range: createRange(document, usage.nameStart, usage.nameEnd),
      message: `"${componentDisplay}" requires the \`patch\` attribute.`,
      source: 'phoenix-lsp',
      code: 'live-patch-missing-patch',
    });
  }
}

function validateLiveRedirect(
  document: TextDocument,
  usage: ComponentUsage,
  componentDisplay: string,
  diagnostics: Diagnostic[]
) {
  if (!hasAttribute(usage, 'navigate')) {
    diagnostics.push({
      severity: DiagnosticSeverity.Error,
      range: createRange(document, usage.nameStart, usage.nameEnd),
      message: `"${componentDisplay}" requires the \`navigate\` attribute.`,
      source: 'phoenix-lsp',
      code: 'live-redirect-missing-navigate',
    });
  }
}

function validateLiveComponentInvocation(
  document: TextDocument,
  usage: ComponentUsage,
  componentDisplay: string,
  diagnostics: Diagnostic[]
) {
  const hasModule = hasAttribute(usage, 'module');
  const hasId = hasAttribute(usage, 'id');
  const hasFor = hasAttribute(usage, ':for');

  if (!hasModule) {
    diagnostics.push({
      severity: DiagnosticSeverity.Error,
      range: createRange(document, usage.nameStart, usage.nameEnd),
      message: `"${componentDisplay}" requires the \`module\` attribute pointing to a LiveComponent module.`,
      source: 'phoenix-lsp',
      code: 'live-component-missing-module',
    });
  }

  if (!hasId && !hasFor) {
    diagnostics.push({
      severity: DiagnosticSeverity.Error,
      range: createRange(document, usage.nameStart, usage.nameEnd),
      message: `"${componentDisplay}" requires a unique \`id\` (or \`:for\` to derive one).`,
      source: 'phoenix-lsp',
      code: 'live-component-missing-id',
    });
  }
}

const jsPushMissingEventPattern = /JS\.push\(\s*\)/g;
const jsPushEmptyStringPattern = /JS\.push\(\s*(["'])(.*?)\1/g;

export function validateJsPushUsage(document: TextDocument, text: string): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];

  let match: RegExpExecArray | null;
  jsPushMissingEventPattern.lastIndex = 0;
  while ((match = jsPushMissingEventPattern.exec(text)) !== null) {
    diagnostics.push({
      severity: DiagnosticSeverity.Warning,
      range: createRange(document, match.index, match.index + match[0].length),
      message: '`JS.push/2` expects an event name as the first argument.',
      source: 'phoenix-lsp',
      code: 'js-push-missing-event',
    });
  }

  jsPushEmptyStringPattern.lastIndex = 0;
  while ((match = jsPushEmptyStringPattern.exec(text)) !== null) {
    const eventName = match[2]?.trim() ?? '';
    if (eventName.length === 0) {
      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: createRange(document, match.index, match.index + match[0].length),
        message: '`JS.push/2` event name should not be empty.',
        source: 'phoenix-lsp',
        code: 'js-push-empty-event',
      });
    }
  }

  return diagnostics;
}
