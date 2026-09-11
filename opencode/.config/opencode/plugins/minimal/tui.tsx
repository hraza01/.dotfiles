/** @jsxImportSource @opentui/solid */
import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui";

const id = "minimal";

const tui: TuiPlugin = async (api) => {
  api.theme.set("system");

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
  });
};

const plugin: TuiPluginModule = { id, tui };
export default plugin;
