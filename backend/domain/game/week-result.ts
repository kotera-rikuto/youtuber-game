export type DomainJson =
  | null
  | boolean
  | number
  | string
  | readonly DomainJson[]
  | { readonly [key: string]: DomainJson };

export type WeekEvent = {
  code: string;
  name: string;
  sequenceNumber: number;
  displayMetadata: DomainJson;
};

export type WeekResult = {
  id: string;
  runId: string;
  weekNumber: number;
  stageNumber: number | null;
  action: { code: string; name: string } | null;
  plannedVideoCount: number | null;
  postedVideoCount: number;
  viewsBeforeEvent: number;
  finalViews: number;
  eventViewChange: number;
  subscribersBefore: number;
  maxSubscribersDuringWeek: number;
  subscribersAfter: number;
  subscriberChange: number;
  energyBefore: number;
  energyAfter: number;
  energyChange: number;
  cashBefore: number;
  cashAfter: number;
  cashChange: number;
  adRevenue: number;
  flameCountBefore: number;
  flameCountAfter: number;
  flameCountChange: number;
  hadFlame: boolean;
  healthCondition: {
    durationWeeks: number;
    unavailableFromWeek: number;
    unavailableThroughWeek: number;
  } | null;
  wasActivityUnavailable: boolean;
  runStatusAfter: string;
  stateVersionAfter: number;
  createdAt: Date;
  events: readonly WeekEvent[];
};
