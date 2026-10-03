# Camera stack completion — wide, zoom, color (plan, 2026-10-03)

Written-by: Fulgor Nymvale (agent-fulgor-zcode)
Agent-harness: ZCode:GLM-5.3-Flash
Date: 2026-10-03
Status: plan; queued behind the running slim2/audio/HI553 agents

Lance asks (2026-10-03): wide camera support, plus proper zoom and color
support for the working back camera. Current state + path for each:

## 1. Color — IMX351 CCM (closest to done)
- Base libcamera tuning file committed: pmaports `temp/libcamera/imx351.yaml`
  (d1237440fb, r5). LG's own colour matrices were extracted 2026-09-26 from
  the vendor lib and sit UNCOMMITTED on top of it (Ember's rule: never ship
  untested).
- Path: bench capture A/B (defaults vs LG CCM) against a reference target;
  ship if measurably better. Then drop the -M.
- Estimate: one bench session, no kernel work.

## 2. Zoom — IMX351 digital zoom via libcamera ScalerCrop
- joan has no optical zoom (fixed lenses); "zoom" = sensor/VFE crop +
  upscale. The camss VFE supports cropping; the work is wiring libcamera's
  controls::ScalerCrop to the IMX351 subdev crop/compose rects (set_selection)
  and verifying the VFE honors it; then the camera apps (libhandy/pipewire
  camera stack) can expose a zoom slider.
- Path: kernel IMX351 driver gets .set_selection (native crop bins);
  libcamera pipeline gets ScalerCrop plumbed; simple cam test with
  `cam -c1 --stream ... --zoom`.
- Estimate: small kernel patch + medium libcamera work.

## 3. Wide — Samsung S5K3M3 (rear wide, CSIPHY1, fixed focus)
- Not started. Same recipe as the in-flight HI553 front port:
  register tables live in the vendor userspace lib (libmmcamera_s5k3m3.so),
  extracted like the IMX351 CCM; V4L2 subdev modeled on imx351.c/hi553.c;
  DT node on CSIPHY1; fixed focus = no actuator.
- The HI553 port (running) proves the recipe end to end; the wide port
  reuses its tooling (register-table parser) and diff review.
- Estimate: medium; one bench session for bring-up + still capture.

Order: 1 (color test) rides any camera bench window; 2 (zoom) after;
3 (wide) starts as an agent the moment a slot frees after HI553 v3
completes (recipe proven = highest success probability then).
