import {
  Card,
  CardContent,
  CardDescription,
  CardTitle,
  Icon,
  Marquee,
  Section,
  Spacer,
  Stack,
  Toolbar,
  ToolbarButton,
  useMedia,
} from "@notchapp/api";

export default function Widget() {
  const media = useMedia();
  const title = media.item?.title ?? "Nothing Playing";
  const secondaryText = media.item?.artist ?? media.item?.album;
  const canOpenSourceApp = media.availableActions.includes("openSourceApp");
  const canPreviousTrack = media.availableActions.includes("previousTrack");
  const canTogglePlayback = media.availableActions.includes("togglePlayPause");
  const canNextTrack = media.availableActions.includes("nextTrack");
  const playbackSymbol = media.playbackState === "playing" ? "pause.fill" : "play.fill";

  return (
    <Section spacing="lg" alignment="leading">
      <Card
        variant="accent"
        size="sm"
        strokeWidth={0}
        onClick={canOpenSourceApp ? () => media.openSourceApp() : undefined}
      >
        <CardContent
          spacing={0}
          alignment="center"
          inset="none"
          padding={{ top: 12, leading: 12, trailing: 12, bottom: 14 }}
        >
          <Spacer />
          <Stack spacing="sm" alignment="center" frame={{ maxWidth: Infinity }}>
            <Icon symbol="music.note" size={18} weight="semibold" tone="accent" />
            <Stack spacing="xs" alignment="center" frame={{ maxWidth: Infinity }}>
              <Marquee active={media.playbackState === "playing"}>
                <CardTitle alignment="center" lineClamp={1}>
                  {title}
                </CardTitle>
              </Marquee>
              {secondaryText ? (
                <Marquee active={media.playbackState === "playing"}>
                  <CardDescription alignment="center" lineClamp={1}>
                    {secondaryText}
                  </CardDescription>
                </Marquee>
              ) : null}
            </Stack>
          </Stack>
        </CardContent>
      </Card>

      <Toolbar spacing="lg" alignment="center">
        <ToolbarButton
          symbol="backward.fill"
          variant="secondary"
          size="md"
          disabled={!canPreviousTrack}
          onClick={canPreviousTrack ? () => media.previousTrack() : undefined}
        />
        <ToolbarButton
          symbol={playbackSymbol}
          variant="default"
          size="xl"
          disabled={!canTogglePlayback}
          onClick={canTogglePlayback ? () => media.togglePlayPause() : undefined}
        />
        <ToolbarButton
          symbol="forward.fill"
          variant="secondary"
          size="md"
          disabled={!canNextTrack}
          onClick={canNextTrack ? () => media.nextTrack() : undefined}
        />
      </Toolbar>
    </Section>
  );
}
