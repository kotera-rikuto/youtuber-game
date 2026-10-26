import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "ゆーちゅーばーになろう！（仮）",
  description: "YouTuber育成シミュレーションゲームの開発プロジェクト",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
