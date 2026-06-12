# Scene Ink Web Prototype

Vite browser prototype for turning camera input into brush strokes with pointer input.

Run locally:

```sh
npm install
npm run dev
```

Open the local URL shown by Vite. For mobile devices on the same Wi-Fi, open the network HTTPS URL, for example `https://<mac-lan-ip>:5173/`.

Camera access requires a secure context. This Vite setup uses a self-signed development certificate, so mobile browsers may ask you to accept the certificate warning before camera permission appears.

For iOS Home Screen use, open the HTTPS URL in Safari and choose Share -> Add to Home Screen. The app includes standalone-mode metadata, a touch icon, and a web manifest.

The renderer currently uses Canvas 2D with offscreen canvases. WebGPU is not required, so the prototype stays usable on Safari versions where WebGPU is unavailable or disabled.
