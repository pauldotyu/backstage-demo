import { createApp } from "@backstage/frontend-defaults";
import catalogPlugin from "@backstage/plugin-catalog/alpha";
import { navModule } from "./modules/nav";
import { homeModule } from "./modules/home";
import { microsoftAuthApiRef } from "@backstage/core-plugin-api";
import { SignInPageBlueprint } from "@backstage/plugin-app-react";
import { SignInPage } from "@backstage/core-components";
import { createFrontendModule } from "@backstage/frontend-plugin-api";

const signInPage = SignInPageBlueprint.make({
  params: {
    loader: async () => (props) => (
      <SignInPage
        {...props}
        provider={{
          id: "microsoft-auth-provider",
          title: "Microsoft Entra ID",
          message: "Sign in using Microsoft Entra ID",
          apiRef: microsoftAuthApiRef,
        }}
      />
    ),
  },
});

export default createApp({
  features: [
    catalogPlugin,
    navModule,
    homeModule,
    createFrontendModule({
      pluginId: "app",
      extensions: [signInPage],
    }),
  ],
});
