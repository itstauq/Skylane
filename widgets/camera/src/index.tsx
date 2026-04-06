import {
  Camera,
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuErrorItem,
  DropdownMenuLoadingItem,
  DropdownMenuSeparator,
  DropdownMenuTriggerButton,
  Overlay,
  useCameras,
  usePreference,
} from "@notchapp/api";

export default function Widget() {
  const cameras = useCameras();
  const [mirrorPreview, setMirrorPreview] = usePreference("mirrorPreview");

  return (
    <Camera
      deviceId={cameras.value}
      mirrored={mirrorPreview ?? true}
    >
      <Overlay placement="top-end" inset="sm">
        <DropdownMenu
          trigger={(
            <DropdownMenuTriggerButton
              symbol="gearshape.fill"
              appearance="overlay"
            />
          )}
        >
          {cameras.isLoading && cameras.items.length === 0 ? (
            <DropdownMenuLoadingItem>Loading Cameras…</DropdownMenuLoadingItem>
          ) : cameras.error && cameras.items.length === 0 ? (
            <DropdownMenuErrorItem error={cameras.error} fallback="Unable to load cameras" />
          ) : (
            cameras.items.map((camera) => (
              <DropdownMenuCheckboxItem
                key={camera.id}
                checked={camera.id === cameras.value}
                onClick={() => cameras.setValue(camera.id)}
              >
                {camera.name}
              </DropdownMenuCheckboxItem>
            ))
          )}
          <DropdownMenuSeparator />
          <DropdownMenuCheckboxItem
            checked={mirrorPreview ?? true}
            onCheckedChange={setMirrorPreview}
          >
            Mirror Preview
          </DropdownMenuCheckboxItem>
        </DropdownMenu>
      </Overlay>
    </Camera>
  );
}
