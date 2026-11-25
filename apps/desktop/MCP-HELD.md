# Remote MCP, held back

Remote MCP ([MCP-PLAN.md](MCP-PLAN.md), #863) is off in release builds until
Wain accounts (#874) land, so its sign-in can go through wainhq.com (#900).
Dev builds keep all of it. Nothing was deleted; this is the list to undo.

## The switch

Two lines, flipped together:

- `REMOTE_MCP` in [crates/wain-proto/src/lib.rs](../../crates/wain-proto/src/lib.rs):
  the server's `/mcp`, `/oauth/*` and `/.well-known/oauth-*` routes, the
  `mcp_*` serve commands, the socket's assistant verbs, and
  `wain server assistant` in the CLI's help.
- `REMOTE_MCP` in [ServersSettings.tsx](src/components/settings/ServersSettings.tsx):
  Connect an assistant… and the assistant list under each server.

Set both to `true`, or delete them and the conditions they guard.

## Text to put back

**Docs page.** Move `apps/docs/held/reference/assistants.mdx` back to
`apps/docs/content/reference/`. The pages after it kept their sidebar order,
so it slots back in at 2.

**CLI docs.** In `apps/docs/content/cli/servers.mdx`, the table row after
`wain login` / `wain logout`:

```md
| `assistant add` / `ls` / `revoke <id>` | Connects Grok, Claude or ChatGPT to the server, lists the ones connected, or signs one out. See [Connect an assistant](/reference/assistants). |
```

and this section before `### Link to an org`:

````md
### Assistants

```bash
wain server assistant add
wain server assistant add --read-only
wain server assistant ls
wain server assistant revoke <id>
```

`add` prints the URL to add as a custom connector in Grok, Claude or ChatGPT, and a code the connector's sign-in asks for. The code works once, for 10 minutes. It turns on the public address first if it is off, and waits for it. `--read-only` makes an assistant that can list and read sessions but not change them.

`ls` lists the assistants signed in, with their id, name, access and when each was last used. `revoke` signs one out at once. See [Connect an assistant](/reference/assistants).
````

**The `wain` skill.** In `apps/cli/skill/SKILL.md`, under "This machine's
server", after `wain server pair`:

```bash
wain server assistant add   # a URL and one-time code to connect Grok, Claude or ChatGPT over MCP; --read-only
wain server assistant ls    # the assistants signed in; revoke <id> signs one out
```

and the paragraph below it ends:

```md
apart from `tunnel`, which is the Remote access button in Settings → Servers,
and `assistant`, which is Connect an assistant there. The code `assistant add`
prints is a sign-in for the user's own assistant: hand it to the user, never
to a service yourself.
```

**Changelog.** Nothing to restore: no entry was written. Add one under the
release that ships it.
