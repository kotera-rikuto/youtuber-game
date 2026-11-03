import "server-only";

import { createClient } from "@supabase/supabase-js";

import type { Database } from "@/backend/infrastructure/supabase/database.types";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";

export function createTrustedSupabaseClient(): DatabaseClient {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const secretKey = process.env.SUPABASE_SECRET_KEY;

  if (!url || !secretKey) {
    throw new Error("Supabase のサーバー専用接続情報が設定されていません。");
  }

  return createClient<Database>(url, secretKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });
}
