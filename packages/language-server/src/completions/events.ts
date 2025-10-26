import * as path from 'path';
import { CompletionItem, CompletionItemKind, Position, TextEdit } from 'vscode-languageserver/node';
import { EventsRegistry } from '../events-registry';

const SEND_SELF_ATOM = /send\s*\(\s*self\s*\(\s*\)\s*,\s*:([a-z_][a-z0-9_]*)?$/;
const SEND_SELF_TUPLE_ATOM = /send\s*\(\s*self\s*\(\s*\)\s*,\s*\{\s*:([a-z_][a-z0-9_]*)?$/;

export function getHandleInfoEventCompletions(
  linePrefix: string,
  position: Position,
  filePath: string,
  eventsRegistry: EventsRegistry
): CompletionItem[] | null {
  const match = SEND_SELF_ATOM.exec(linePrefix) || SEND_SELF_TUPLE_ATOM.exec(linePrefix);
  if (!match) {
    return null;
  }

  const partial = match[1] ?? '';
  const infoEvents = eventsRegistry.getHandleInfoEventsFromFile(filePath);
  if (infoEvents.length === 0) {
    return null;
  }

  const startCharacter = position.character - partial.length;
  const range = {
    start: { line: position.line, character: startCharacter },
    end: position,
  };

  return infoEvents.map((event, index) => ({
    label: `:${event.name}`,
    kind: CompletionItemKind.Event,
    detail: `handle_info in ${path.basename(event.filePath)}`,
    documentation: `Defined at line ${event.line}`,
    textEdit: TextEdit.replace(range, `:${event.name}`),
    sortText: `!0${index.toString().padStart(3, '0')}`,
  }));
}
