# Native tool package v1

## Root document

Required fields:

```json
{
  "schemaVersion": 1,
  "name": "Tool name",
  "stateVersion": 1,
  "initialState": {},
  "screens": [{"id":"main","title":"Tool name","components":[]}],
  "actions": {},
  "capabilities": []
}
```

Optional `summary` (up to 500 characters) and `symbol` (SF Symbol name). Name is limited to 80 characters. IDs/state keys/action names match `[A-Za-z][A-Za-z0-9_-]{0,63}`. The first screen is the home screen. Component IDs must be unique across the package, including list templates. Limits: 256 KB package, 12 screens, 200 components, 8 component nesting levels, 100 state keys/actions, 32 steps/action. Runtime state is limited to 1 MB and 500 records/collection.

`initialState` is a dictionary of typed JSON values. Input bindings target top-level keys. Collections are arrays of objects; each initial record needs a unique string `id`. Normally begin with an empty array; append assigns IDs. Initial values are used only for new keys when updating, never to overwrite saved user data. State types and stateVersion cannot change in v1. Preserve existing keys when editing. Do not place real user data or credentials in initialState.

Optional `sessionState` declares transient typed values (up to 100 keys, disjoint from initialState). Use empty strings/objects/arrays for host results and password inputs. It is never persisted and resets when the tool closes, the app becomes inactive/backgrounded, or the credential session changes. `get` can read either state dictionary. Optional `onRefresh` names an action run when opened and once per second while visible; that action may only invoke catalog operations with `passive: true`. It cannot activate camera, files, authentication or writes.

## Components

Every component requires `id` and `type`. Optional fields: `title`, `value`, `binding`, `sessionBinding`, `action`, `children`, `options`, `visibleWhen`. `value` and `visibleWhen` are expressions. `action` refers to a key in root actions. Use either `binding` for initialState or `sessionBinding` for sessionState, never both. Only use fields applicable to the component.

| type | Fields and behavior |
| --- | --- |
| text, heading | value expression; title is a fallback |
| value | title label and value expression |
| stack, row | children; vertical or horizontal layout |
| section | title and children; native group |
| divider | no additional fields |
| textField | title and binding to a string |
| secureField | title and sessionBinding to a string; masked password/secret input, never persistent |
| numberField | title and binding to a number |
| toggle | title and binding to a boolean |
| picker | title, string binding, unique string options including the initial value |
| button | nonempty title and action name |
| list | either binding to persistent records or value expression returning records (e.g. a host result); children as repeated row template; optional title for empty collection; no nested lists |
| progress | title and value expression in range 0…1 |
| countdown | title and value expression returning a Unix timestamp in seconds; updates only while visible; no background notification |

Inside a list template, expressions can read the current record with `{"item":"fieldName"}`; `{"item":""}` returns the record. Actions triggered from the row receive that record. Use root state for input fields; to edit a record, build explicit state/actions within the supported operations.

## Expressions

Literals are normal JSON primitives. Arrays and ordinary objects evaluate recursively. Reserved expression objects:

- `{"get":"stateKey"}`: current state value.
- `{"item":"field"}`: current list record field.
- `{"now":true}`: current device Unix time in seconds.
- `{"op":"name","args":[...]}`: bounded operation tree, maximum depth 16 and 16 arguments.

Operations:

- Binary numeric: add, subtract, multiply, divide, min, max. Division by zero is an error.
- Unary numeric: round.
- Text: concat (0…16 args), trim, uppercase, lowercase (one arg), contains (two args, case-insensitive substring).
- Collection: count (one array or string), sum (array of records and numeric field name, or array of numbers produced by an expression).
- Object: field (object, string field name); reads one property, returns null if absent.
- Filter: filter (array of records, string field name, search text); case-insensitive substring match; empty search returns all records.
- Conditions: equal, greater, less (two args), not (one), and/or (0…16), if (condition, true branch, false branch). if evaluates only the selected branch.

Example: `{"op":"multiply","args":[{"get":"meters"},100]}`.
An ordinary object for append can contain expressions: `{"title":{"get":"draft"},"done":false}`. Reserved object keys get/item/now/op are interpreted as expressions; do not use them as literal record field names.

## Actions

Each named action is a list of steps. Every step has `type`, optionally `key`, `value`, `field`, `screen`, `when`, `operation`, `arguments`, `result`. `when` conditionally skips a step. Pure persistent actions keep transactional behavior. Actions involving session state or capabilities run sequentially and stop on failure/cancellation; completed native effects cannot be rolled back by later steps. Do not claim an entire multi-capability action is atomic.

- `set`: key and value expression; preserves the declared state type.
- `append`: array key and value expression producing a record object; host assigns/overwrites its id with a UUID.
- `remove`: array key; value optionally supplies a record ID, otherwise uses the current list record ID.
- `toggleItem`: array key and boolean field; optional value supplies record ID, otherwise uses current list record ID.
- `navigate`: screen ID from the screens array.
- `setSession`: session key and value expression; preserves the declared type.
- `invoke`: operation from native_tool_capabilities, expression-valued arguments, optional result naming a sessionState object. The operation's capability must be declared. See capabilities.md.

Persistent mutations cannot read session keys. In packages with sessionState, set/append also cannot copy list item values into persistent storage. Keep host-derived data in sessionState or its native storage capability.

```json
"add": [
  {"type":"append","key":"tasks","value":{"title":{"get":"draft"},"done":false},"when":{"get":"draft"}},
  {"type":"set","key":"draft","value":""}
]
```

## Host capabilities

Use `capabilities: []` for ordinary offline tools. Supported namespaces are `camera`, `photos`, `files`, `clipboard`, `dialog`, and `otp`; discover operations and parameter/result shapes with native_tool_capabilities. Declaring a namespace authorizes matching invoke actions within the tool runtime, subject to platform/user permissions. It does not expose the capability to Agent execution. TOTP is composed from ordinary components and these operations; the old opaque `totp` component is rejected for newly authored packages. Real secrets must never appear in source.

## Installation and updates

Write the source JSON with file_write, validate with native_tool_validate, then install with native_tool_install. For edits, first native_tool_read; supply tool_id and expected_revision during install. These are tool-call arguments, not package fields. Tool IDs and revisions are host-owned. Installation does not share runtime data with the Agent. Updates preserve existing state and store the previous package for UI rollback. A rollback changes the interface/logic and retains current data.

The open link returned by the installer uses `omnibot-tool://open/<UUID>`. Return it as a Markdown link. The tool library also supports native package import/export; exported packages contain source and initial values, not saved data or credentials.
