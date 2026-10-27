import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    files: ["backend/domain/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: [
                "next",
                "next/*",
                "react",
                "react/*",
                "server-only",
                "@supabase/*",
                "openai",
                "@/backend/application/**",
                "@/backend/infrastructure/**",
                "@/backend/queries/**",
                "@/backend/actions/**",
              ],
              message:
                "Domain must stay framework- and service-independent. Depend only on other Domain modules.",
            },
          ],
        },
      ],
      "no-restricted-properties": [
        "error",
        {
          object: "process",
          property: "env",
          message: "Inject configuration instead of reading environment variables in Domain.",
        },
        {
          object: "Date",
          property: "now",
          message: "Inject a Clock instead of reading the current time in Domain.",
        },
        {
          object: "Math",
          property: "random",
          message: "Inject a RandomSource instead of using Math.random in Domain.",
        },
      ],
    },
  },
  {
    files: ["backend/application/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: [
                "next",
                "next/*",
                "react",
                "react/*",
                "server-only",
                "@supabase/*",
                "openai",
                "@/backend/infrastructure/**",
                "@/backend/queries/**",
                "@/backend/actions/**",
              ],
              message:
                "Application may depend on Domain and its own ports, not UI, frameworks, or adapters.",
            },
          ],
        },
      ],
      "no-restricted-properties": [
        "error",
        {
          object: "process",
          property: "env",
          message: "Read environment variables in Infrastructure and inject the value.",
        },
        {
          object: "Date",
          property: "now",
          message: "Use the injected Clock port.",
        },
        {
          object: "Math",
          property: "random",
          message: "Use the injected RandomSource port.",
        },
      ],
    },
  },
  globalIgnores([
    ".next/**",
    ".vinext/**",
    ".cloudflare/**",
    "dist/**",
    "next-env.d.ts",
    "cloudflare-env.d.ts",
  ]),
]);
