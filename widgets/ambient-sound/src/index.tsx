import * as React from "react";
import {
  Icon,
  IconButton,
  Inline,
  RoundedRect,
  Spacer,
  Stack,
  Text,
  useAudio,
  useLocalStorage,
  useTheme,
} from "@skylane/api";

const DEFAULT_SOUNDS = [
  { title: "Rain", icon: "cloud.rain.fill", volume: 4, asset: "rain.m4a" },
  { title: "Fire", icon: "flame.fill", volume: 1, asset: "fire.m4a" },
  { title: "Waves", icon: "water.waves", volume: 1, asset: "waves.m4a" },
  { title: "Forest", icon: "leaf.fill", volume: 0, asset: "forest.m4a" },
  { title: "Wind", icon: "wind", volume: 2, asset: "wind.m4a" },
  { title: "Lo-fi", icon: "music.note.list", volume: 0, asset: "lofi.m4a" },
];

function normalizeSounds(value) {
  if (!Array.isArray(value)) {
    return DEFAULT_SOUNDS;
  }

  const sounds = value.map((item, index) => {
    const fallback = DEFAULT_SOUNDS[index];
    const volume = Number.isInteger(item?.volume)
      ? item.volume
      : (fallback?.volume ?? 0);

    return {
      title:
        typeof item?.title === "string" ? item.title : (fallback?.title ?? ""),
      icon:
        typeof item?.icon === "string"
          ? item.icon
          : (fallback?.icon ?? "speaker.wave.2.fill"),
      asset:
        typeof item?.asset === "string" ? item.asset : (fallback?.asset ?? ""),
      volume: Math.max(0, Math.min(4, volume)),
    };
  });

  if (sounds.length !== DEFAULT_SOUNDS.length) {
    return DEFAULT_SOUNDS;
  }

  return sounds;
}

function withAlpha(color, alpha) {
  if (typeof color !== "string") {
    return color;
  }

  const normalized = color.startsWith("#") ? color.slice(1) : color;
  if (normalized.length < 6) {
    return color;
  }

  return `#${normalized.slice(0, 6)}${alpha}`;
}

function tileFillForVolume(accent, volume, isPlaying) {
  if (!isPlaying) {
    return "#FFFFFF0A";
  }

  switch (volume) {
    case 4:
      return withAlpha(accent, "32");
    case 3:
      return withAlpha(accent, "2A");
    case 2:
      return withAlpha(accent, "22");
    case 1:
      return withAlpha(accent, "16");
    default:
      return "#FFFFFF0A";
  }
}

function playerIdForSound(sound) {
  return sound.asset;
}

function assetSourceForSound(sound) {
  return `assets/${sound.asset}`;
}

function playbackVolumeForLevel(level) {
  switch (level) {
    case 4:
      return 1;
    case 3:
      return 0.72;
    case 2:
      return 0.5;
    case 1:
      return 0.28;
    default:
      return 0;
  }
}

function VolumeBar({ active, selected, index, accent, isPlaying, mutedColor }) {
  return (
    <Stack spacing={0} frame={{ width: 8, height: 10.5 }}>
      <Spacer />
      <RoundedRect
        fill={
          isPlaying
            ? active
              ? selected
                ? accent
                : "#FFFFFF52"
              : "#FFFFFF14"
            : active
              ? mutedColor
              : "#FFFFFF10"
        }
        cornerRadius={999}
        width={8}
        height={3 + index * 2.5}
      />
    </Stack>
  );
}

function SoundTile({ sound, accent, textColor, mutedColor, isPlaying }) {
  const selected = sound.volume >= 1;
  const resolvedTextColor = !isPlaying
    ? mutedColor
    : selected
      ? textColor
      : mutedColor;
  const resolvedIconColor = !isPlaying
    ? mutedColor
    : selected
      ? accent
      : mutedColor;

  return (
    <RoundedRect
      onPress={sound.onClick}
      fill={tileFillForVolume(accent, sound.volume, isPlaying)}
      cornerRadius={12}
      frame={{ maxWidth: Infinity }}
    >
      <Stack
        spacing={5}
        alignment="center"
        padding={{ top: 8, bottom: 8, leading: 6, trailing: 6 }}
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      >
        <Icon
          symbol={sound.icon}
          size={12}
          weight="semibold"
          color={resolvedIconColor}
        />

        <Text
          size={9}
          weight="semibold"
          alignment="center"
          lineClamp={1}
          minimumScaleFactor={0.85}
          color={resolvedTextColor}
        >
          {sound.title}
        </Text>

        <Inline alignment="end" spacing={3} frame={{ height: 10.5 }}>
          {[0, 1, 2, 3].map((index) => (
            <VolumeBar
              key={index}
              active={index < sound.volume}
              selected={selected}
              index={index}
              accent={accent}
              isPlaying={isPlaying}
              mutedColor={mutedColor}
            />
          ))}
        </Inline>
      </Stack>
    </RoundedRect>
  );
}

export default function Widget() {
  const theme = useTheme();
  const audio = useAudio();
  const [storedSounds, setStoredSounds] = useLocalStorage(
    "sounds",
    DEFAULT_SOUNDS,
  );
  const [isPlaying, setIsPlaying] = React.useState(false);
  const [syncError, setSyncError] = React.useState(null);
  const sounds = normalizeSounds(storedSounds);
  const accent = "#75D1B8";
  const textColor = withAlpha(theme.colors.foreground, "E0");
  const mutedColor = withAlpha(theme.colors.foreground, "8F");
  const activeCount = sounds.filter((sound) => sound.volume > 0).length;
  const isMasterPaused = activeCount > 0 && !isPlaying;
  const playersRef = React.useRef(audio.players);
  const soundStateKey = sounds
    .map((sound) => `${sound.asset}:${sound.volume}`)
    .join("|");
  const statusText =
    syncError ?? (isPlaying ? `${activeCount} active` : "All sounds paused");

  React.useEffect(() => {
    playersRef.current = audio.players;
  }, [audio.players]);

  React.useEffect(() => {
    let cancelled = false;

    async function syncAudio() {
      const existingPlayers = new Map(
        playersRef.current.map((player) => [player.id, player]),
      );

      if (isPlaying) {
        for (const sound of sounds) {
          if (cancelled) {
            return;
          }

          const playerId = playerIdForSound(sound);
          if (sound.volume > 0) {
            await audio.play({
              playerId,
              src: assetSourceForSound(sound),
              loop: true,
              volume: playbackVolumeForLevel(sound.volume),
            });
          } else {
            await audio.stop(playerId);
          }
        }

        if (!cancelled) {
          await audio.resumeAll();
          setSyncError(null);
        }
        return;
      }

      for (const sound of sounds) {
        if (cancelled) {
          return;
        }

        const playerId = playerIdForSound(sound);
        if (sound.volume === 0) {
          await audio.stop(playerId);
          continue;
        }

        if (existingPlayers.has(playerId)) {
          await audio.setVolume(playerId, playbackVolumeForLevel(sound.volume));
        }
      }

      if (!cancelled) {
        await audio.pauseAll();
      }
    }

    void syncAudio().catch((error) => {
      if (cancelled) {
        return;
      }

      setSyncError(
        error instanceof Error && error.message.trim() !== ""
          ? error.message
          : "Unable to play sounds",
      );
      setIsPlaying(false);
    });

    return () => {
      cancelled = true;
    };
  }, [
    audio.pauseAll,
    audio.play,
    audio.resumeAll,
    audio.setVolume,
    audio.stop,
    isPlaying,
    soundStateKey,
  ]);

  function cycleVolume(title) {
    setStoredSounds((current) =>
      normalizeSounds(current).map((sound) =>
        sound.title === title
          ? { ...sound, volume: (sound.volume + 1) % 5 }
          : sound,
      ),
    );
  }

  return (
    <Stack spacing={8} frame={{ maxWidth: Infinity, maxHeight: Infinity }}>
      <Inline alignment="center" spacing={8} frame={{ maxWidth: Infinity }}>
        <Text
          size={11}
          weight="semibold"
          lineClamp={1}
          minimumScaleFactor={0.85}
          color={
            isPlaying ? withAlpha(theme.colors.foreground, "D1") : textColor
          }
        >
          {statusText}
        </Text>

        <Spacer />

        <IconButton
          symbol={isPlaying ? "pause.fill" : "play.fill"}
          variant="ghost"
          width={18}
          height={18}
          iconSize={11}
          onClick={() => {
            if (!isPlaying) {
              setSyncError(null);
            }
            setIsPlaying((current) => current !== true);
          }}
        />
      </Inline>

      <Stack
        spacing={6}
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
        overlay={
          isMasterPaused ? (
            <RoundedRect
              onPress={() => {
                setSyncError(null);
                setIsPlaying(true);
              }}
              fill="#06110ED8"
              strokeColor="#FFFFFF14"
              strokeWidth={1}
              cornerRadius={16}
              frame={{ maxWidth: Infinity, maxHeight: Infinity }}
            >
              <Stack
                spacing={5}
                alignment="center"
                frame={{ maxWidth: Infinity, maxHeight: Infinity }}
              >
                <Icon
                  symbol="play.circle.fill"
                  size={18}
                  weight="semibold"
                  color={accent}
                />
                <Text
                  size={11}
                  weight="semibold"
                  alignment="center"
                  color={textColor}
                  frame={{ maxWidth: Infinity }}
                >
                  Paused
                </Text>
                <Text
                  size={9}
                  alignment="center"
                  color={mutedColor}
                  frame={{ maxWidth: Infinity }}
                >
                  Tap to resume your mix
                </Text>
              </Stack>
            </RoundedRect>
          ) : null
        }
      >
        <Inline spacing={6} frame={{ maxWidth: Infinity }}>
          {sounds.slice(0, 3).map((sound) => (
            <SoundTile
              key={sound.title}
              sound={{ ...sound, onClick: () => cycleVolume(sound.title) }}
              accent={accent}
              textColor={textColor}
              mutedColor={mutedColor}
              isPlaying={isPlaying}
            />
          ))}
        </Inline>

        <Inline spacing={6} frame={{ maxWidth: Infinity }}>
          {sounds.slice(3).map((sound) => (
            <SoundTile
              key={sound.title}
              sound={{ ...sound, onClick: () => cycleVolume(sound.title) }}
              accent={accent}
              textColor={textColor}
              mutedColor={mutedColor}
              isPlaying={isPlaying}
            />
          ))}
        </Inline>
      </Stack>
    </Stack>
  );
}
