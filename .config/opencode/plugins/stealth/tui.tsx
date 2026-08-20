// @ts-nocheck
/** @jsxImportSource @opentui/solid */
import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui"

const id = "stealth"

const tui: TuiPlugin = async (api) => {
  api.theme.set("system")

  try { await api.plugins.deactivate("internal:home-tips") } catch {}
  try { await api.plugins.deactivate("internal:sidebar-context") } catch {}

  api.slots.register({
    slots: {
      home_logo: () => <box height={0} />,
      home_bottom: () => <box height={0} />,
      home_footer: () => <box height={0} />,
      home_prompt_right: () => <box height={0} />,
      session_prompt_right: () => <box height={0} />,
      sidebar_title: () => <box height={0} />,
      sidebar_footer: () => <box height={0} />,
      app_bottom: () => <box height={0} />,
    },
  })

  api.lifecycle.onDispose(async () => {
    try { await api.plugins.activate("internal:home-tips") } catch {}
    try { await api.plugins.activate("internal:sidebar-context") } catch {}
  })
}

const plugin: TuiPluginModule & { id: string } = { id, tui }
export default plugin
