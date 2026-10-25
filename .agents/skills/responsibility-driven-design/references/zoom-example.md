# Worked Example: Zoom (TypeScript illustration — translate idiomatically)

Load when designing a feature with several collaborating objects, or reviewing a god service.

Concrete example: "I'm zoomed out and want to read small text, so I zoom in." (Vagueness does not compile.)

## Step 1: responsibilities (unordered)
- Detect mouse scroll; pass the event on.
- Subscribe to "mouse scrolled"; know when the work is done.
- Compute the new zoom; keep it within limits.
- Know the camera's origin and zoom factor.
- Compute the canvas projection from the camera.
- Apply the projection to the canvas.

## Step 2: role map
| Object | Stereotype | Doings / knowings |
|---|---|---|
| WindowAPI | Interfacer | Listen to wheel events, push MouseScrollEvent |
| MouseScrollEvent | Information holder | Knows deltaY |
| ApplicationObserver | Coordinator | Subscribe, notify |
| ZoomController | Controller (≈ use case) | Execute zoom, emit ZoomUpdated |
| Camera | Structurer | Knows origin and zoom factor; rules for zoom limits |
| CanvasService | Service provider | Stateless projection math |
| CanvasAPI | Interfacer | Apply projection to the canvas |

## Step 3: collaborations
Window wheel event → WindowAPI → notify MouseScrollEvent → ApplicationObserver → ZoomController → Camera.zoomBy → notify ZoomUpdated → ZoomUpdatedSubscription → UpdateCanvasProjection use case → CanvasService computes → CanvasAPI applies.

## Before: god service (what an agent generates for "add zoom")
```ts
class CameraService {
  private x = 0; private y = 0; private zoom = 1;

  constructor(private canvas: HTMLCanvasElement) {
    canvas.addEventListener('wheel', (e) => this.onWheel(e));            // IO
  }

  private onWheel(e: WheelEvent) {
    if (!e.ctrlKey) return;
    const next = this.zoom * (e.deltaY < 0 ? 1.1 : 0.9);                 // math
    this.zoom = Math.min(8, Math.max(0.1, next));                        // rules + state
    const ctx = this.canvas.getContext('2d')!;
    ctx.setTransform(this.zoom, 0, 0, this.zoom, -this.x, -this.y);      // rendering
    this.redrawEverything(ctx);
  }
  private redrawEverything(ctx: CanvasRenderingContext2D) { /* ... */ }
}
```

## After: one dominant role per object
```ts
class MouseScrollEvent { readonly name = 'MouseScrolled'; constructor(readonly deltaY: number) {} }   // information holder
class ZoomUpdatedEvent { readonly name = 'ZoomUpdated'; constructor(readonly zoomFactor: number) {} } // information holder

class ApplicationObserver {                                              // coordinator
  private handlers: Record<string, Array<(e: any) => void>> = {};
  subscribe(name: string, fn: (e: any) => void) { (this.handlers[name] ??= []).push(fn); }
  notify(e: { name: string }) { (this.handlers[e.name] ?? []).forEach((fn) => fn(e)); }
}

class WindowAPI {                                                        // interfacer
  constructor(window: Window, observer: ApplicationObserver) {
    window.addEventListener('wheel', (e) => { if (e.ctrlKey) observer.notify(new MouseScrollEvent(e.deltaY)); });
  }
}

class Camera {                                                           // structurer
  constructor(public origin = { x: 0, y: 0 }, public zoomFactor = 1) {}
  zoomBy(deltaY: number) {
    const next = this.zoomFactor * (deltaY < 0 ? 1.1 : 0.9);
    this.zoomFactor = Math.min(8, Math.max(0.1, next));
  }
}

class ZoomController {                                                   // controller
  constructor(private camera: Camera, private observer: ApplicationObserver) {}
  zoom(deltaY: number) {
    this.camera.zoomBy(deltaY);
    this.observer.notify(new ZoomUpdatedEvent(this.camera.zoomFactor));
  }
}

class CanvasService {                                                    // service provider
  project(camera: Camera) { return { scale: camera.zoomFactor, dx: -camera.origin.x, dy: -camera.origin.y }; }
}

// composition root
observer.subscribe('MouseScrolled', (e: MouseScrollEvent) => zoomController.zoom(e.deltaY));
```

## Controllers are called, they don't subscribe
```ts
// Before: a controller/interfacer subscribing itself
class CanvasAPI {
  constructor(observer: ApplicationObserver) {
    observer.subscribe('ZoomUpdated', (e) => this.updateProjection(e));
  }
  updateProjection(e: ZoomUpdatedEvent) { /* compute + draw */ }
}

// After: a subscription object calls the use case
class ZoomUpdatedSubscription {
  constructor(observer: ApplicationObserver, private updateCanvasProjection: UpdateCanvasProjection) {
    observer.subscribe('ZoomUpdated', (e) => this.updateCanvasProjection.execute(e));
  }
}
```

## From design to code (critique lessons)
- Upfront design is a theoretical guess; it is only real in test form. Relax certainty.
- Write the first test at the application level, readable as a scenario:
  ```gherkin
  Scenario: Zoom in to read small text
    Given the camera is at zoom factor 1
    When the user scrolls the mouse wheel up
    Then the camera zoom factor should be greater than 1
  ```
- Let red-green-refactor produce the real design. Match rigor to product stage.
- Change inside one use case = vertical slice; updating the canvas after ZoomUpdated is a separate feature = temporal decoupling.
- Make small guesses: sending deltaY to a backend adds reconciliation, network and offline responsibilities. Postpone.
- Extract concepts later (e.g. a ZoomFactor value object) once duplication shows up.
- Frontend responsibilities are real: view data and model data (knowings); updating the view, getting the model, triggering re-render (doings). Most complexity comes from state management: where data belongs and who operates on it.
