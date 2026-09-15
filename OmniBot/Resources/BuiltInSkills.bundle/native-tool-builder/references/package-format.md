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

## Components

Every component requires `id` and `type`. Optional fields: `title`, `value`, `binding`, `action`, `children`, `options`, `visibleWhen`. `value` and `visibleWhen` are expressions. `action` refers to a key in root actions. Bindings refer to declared initialState keys. Only use fields applicable to the component.

| type | Fields and behavior |
| --- | --- |
| text, heading | value expression; title is a fallback |
| value | title label and value expression |
| stack, row | children; vertical or horizontal layout |
| section | title and children; native group |
| divider | no additional fields |
| textField | title and binding to a string |
| numberField | title and binding to a number |
| toggle | title and binding to a boolean |
| picker | title, string binding, unique string options including the initial value |
| button | nonempty title and action name |
| list | binding to an array of records, children as the repeated row template, optional title for an empty collection; no nested lists |
| progress | title and value expression in range 0…1 |
| countdown | title and value expression returning a Unix timestamp in seconds; updates only while visible; no background notification |
| totp | optional title; requires totp capability; use once outside list templates |

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
- Conditions: equal, greater, less (two args), not (one), and/or (0…16), if (condition, true branch, false branch). if evaluates only the selected branch.

Example: `{"op":"multiply","args":[{"get":"meters"},100]}`.
An ordinary object for append can contain expressions: `{"title":{"get":"draft"},"done":false}`. Reserved object keys get/item/now/op are interpreted as expressions; do not use them as literal record field names.

## Actions

Each named action is a list of steps. Every step has `type`, optionally `key`, `value`, `field`, `screen`, `when`. `when` conditionally skips the step. Steps run in order against the updated state and commit together only if all steps succeed.

- `set`: key and value expression; preserves the declared state type.
- `append`: array key and value expression producing a record object; host assigns/overwrites its id with a UUID.
- `remove`: array key; value optionally supplies a record ID, otherwise uses the current list record ID.
- `toggleItem`: array key and boolean field; optional value supplies record ID, otherwise uses current list record ID.
- `navigate`: screen ID from the screens array.

```json
"add": [
  {"type":"append","key":"tasks","value":{"title":{"get":"draft"},"done":false},"when":{"get":"draft"}},
  {"type":"set","key":"draft","value":""}
]
```

## Host capabilities

Use `capabilities: []` for ordinary offline tools. The only optional capability in v1 is `totp`. Declaring it makes the native manager available, but does not grant scripts or generic state access to accounts, secrets or codes. The user unlocks and manages accounts in the host UI; credentials are isolated by installed tool UUID. Real secrets must never appear in the source package.

## Installation and updates

Write the source JSON with file_write, validate with native_tool_validate, then install with native_tool_install. For edits, first native_tool_read; supply tool_id and expected_revision during install. These are tool-call arguments, not package fields. Tool IDs and revisions are host-owned. Installation does not share runtime data with the Agent. Updates preserve existing state and store the previous package for UI rollback. A rollback changes the interface/logic and retains current data.

The open link returned by the installer uses `omnibot-tool://open/<UUID>`. Return it as a Markdown link. The tool library also supports native package import/export; exported packages contain source and initial values, not saved data or credentials.
