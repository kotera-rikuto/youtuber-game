export type PendingIdea = {
  id: string;
  position: number;
  title: string;
  description: string | null;
  createdWeek: number;
  createdAt: Date;
  queuedAt: Date;
};

export type IdeaQueue = {
  runId: string;
  items: readonly PendingIdea[];
};
