# Scene Ink

Vite browser prototype for turning camera input into brush strokes with pointer input.

The app uses the live camera feed as source material. Dragging on the screen samples narrow camera lines along the drag path and composites them into a screen-space stroke.

## Run

```sh
npm install
npm run dev
```

Open the HTTPS URL shown by Vite. For a phone on the same Wi-Fi, use one of the network URLs, for example:

```text
https://<mac-lan-ip>:5173/
```

Camera access requires a secure context. The local Vite setup uses a self-signed certificate, so mobile browsers may show a certificate warning before the camera permission prompt appears.

## iOS Home Screen

Open the HTTPS URL in Safari, then use Share -> Add to Home Screen. The app includes iOS standalone-mode metadata, a touch icon, and a web manifest; camera access still requires the HTTPS origin to be trusted and camera permission to be granted.

## Build

```sh
npm run build
```

## Deploy

The production build is served from GitHub Pages:

```text
https://yamatoiizuka.github.io/scene-ink/
```
