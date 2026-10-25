// Stylised front/back body diagram, drawn from scratch (not traced from any book).
// Single source of truth: the HTML mockup loads this file, and generate-swift.js turns it into the app's data file.
//
// Coordinates: 200 x 440 box, centre line at x = 100. Every shape is written for the LEFT half of the picture
// and is mirrored automatically. A point is [x, y] or [x, y, 1] when the corner must stay sharp (centre seams).
(function (root) {
  const WIDTH = 200;
  const HEIGHT = 440;

  const round1 = (v) => Math.round(v * 10) / 10;

  /** Closed Catmull-Rom spline through the points, written as absolute cubic Beziers. */
  function smoothPath(points) {
    const n = points.length;
    const P = points.map((p) => ({ x: p[0], y: p[1], sharp: p[2] === 1 }));
    const tangent = (i) => {
      if (P[i].sharp) return { x: 0, y: 0 };
      const before = P[(i - 1 + n) % n];
      const after = P[(i + 1) % n];
      return { x: (after.x - before.x) / 6, y: (after.y - before.y) / 6 };
    };
    let d = `M ${round1(P[0].x)} ${round1(P[0].y)}`;
    for (let i = 0; i < n; i++) {
      const from = P[i];
      const to = P[(i + 1) % n];
      const t0 = tangent(i);
      const t1 = tangent((i + 1) % n);
      d += ` C ${round1(from.x + t0.x)} ${round1(from.y + t0.y)} ${round1(to.x - t1.x)} ${round1(to.y - t1.y)} ${round1(to.x)} ${round1(to.y)}`;
    }
    return d + ' Z';
  }

  const mirrorPoints = (points) => points.map(([x, y, sharp]) => (sharp ? [WIDTH - x, y, 1] : [WIDTH - x, y]));

  /** Both halves of one shape. */
  const bothHalves = (points) => [smoothPath(points), smoothPath(mirrorPoints(points))];

  /** A small rounded block, used for the ab segments. */
  const block = (y0, y1) => [[99.5, y0, 1], [91, y0 + 0.6], [90.4, (y0 + y1) / 2], [91, y1 - 0.6], [99.5, y1, 1]];

  // Silhouette pieces drawn dimly behind the muscles. Same for front and back.
  const BASE = [
    [[100, 8, 1], [89, 12], [85, 27], [89, 42], [100, 50, 1]],
    [[100, 46, 1], [91, 48], [90, 62], [96, 68], [100, 68, 1]],
    [[100, 62, 1], [84, 64], [66, 68], [54, 76], [53, 90], [57, 110], [63, 135], [66, 160], [67, 182], [63, 198], [64, 214], [100, 216, 1]],
    [[56, 74], [46, 76], [40, 94], [37, 122], [38, 142], [50, 144], [53, 122], [58, 100], [60, 84]],
    [[49, 142], [38, 143], [32, 168], [26, 200], [34, 204], [44, 184], [53, 154]],
    [[33, 198], [24, 201], [21, 222], [26, 230], [34, 222], [39, 208]],
    [[100, 210, 1], [84, 206], [64, 204], [60, 228], [63, 262], [66, 298], [70, 316], [69, 348], [73, 386], [76, 408], [92, 410], [90, 386], [93, 350], [96, 330], [93, 310], [92, 284], [98, 240], [100, 230, 1]],
    [[76, 406], [70, 420], [72, 432], [93, 432], [91, 414]],
  ];

  // Muscle shapes per view, keyed by part id.
  const FRONT = {
    chest_upper: [[[100, 75, 1], [84, 72], [70, 75], [63, 84], [65, 91], [82, 92], [100, 91, 1]]],
    chest_mid: [[[100, 93, 1], [82, 94], [66, 93], [64, 101], [72, 106], [88, 106], [100, 105, 1]]],
    chest_lower: [[[100, 107, 1], [88, 108], [73, 108], [68, 113], [74, 119], [88, 121], [100, 120, 1]]],
    delt_front: [[[66, 77], [59, 72], [54, 78], [54, 92], [58, 102], [65, 98], [67, 88]]],
    delt_side: [[[53, 78], [48, 74], [43, 80], [42, 92], [46, 101], [52, 102], [53, 90]]],
    traps_upper: [[[91, 55], [80, 59], [68, 66], [60, 72], [66, 75], [76, 70], [88, 66], [92, 65]]],
    biceps: [[[49, 97], [56, 106], [55, 124], [47, 138], [41, 128], [41, 112], [43, 101]]],
    brachialis: [[[40, 122], [43, 118], [45, 132], [43, 142], [39, 138]]],
    forearm_flexors: [[[50, 146], [53, 154], [47, 178], [37, 200], [31, 197], [33, 172], [42, 150]]],
    abs: [block(124, 136), block(138, 151), block(153, 167), block(169, 184)],
    obliques: [[[88, 125], [78, 126], [72, 134], [70, 152], [72, 172], [78, 186], [88, 186], [89, 168], [89, 148]]],
    serratus: [[[74, 106], [67, 110], [66, 121], [71, 128], [76, 121], [77, 111]]],
    quad_rectus: [[[83, 207], [78, 230], [78, 268], [82, 296], [86, 268], [86, 230]]],
    quad_outer: [[[72, 210], [63, 224], [62, 260], [67, 292], [75, 292], [77, 256], [77, 222]]],
    quad_inner: [[[91, 236], [93, 262], [90, 288], [85, 298], [85, 270], [87, 244]]],
    adductors: [[[98, 214], [95, 221], [91, 238], [88, 258], [95, 252], [98, 232]]],
    abductors: [[[62, 197], [56, 207], [58, 222], [66, 227], [72, 215], [70, 201]]],
    tibialis: [[[80, 318], [74, 325], [74, 352], [78, 384], [84, 386], [86, 352], [85, 326]]],
    gastrocnemius: [
      [[69, 320], [65, 332], [67, 352], [72, 358], [73, 332]],
      [[93, 320], [97, 333], [94, 353], [89, 358], [89, 332]],
    ],
  };

  const BACK = {
    traps_upper: [[[100, 54, 1], [88, 58], [74, 66], [62, 72], [70, 78], [84, 74], [100, 72, 1]]],
    traps_mid: [[[100, 76, 1], [84, 78], [70, 84], [66, 90], [84, 90], [100, 90, 1]]],
    traps_lower: [[[100, 113, 1], [90, 115], [85, 125], [88, 145], [100, 156, 1]]],
    rhomboids: [[[100, 92, 1], [85, 92], [77, 96], [78, 108], [90, 112], [100, 110, 1]]],
    lats: [[[79, 106], [69, 104], [62, 116], [62, 136], [68, 158], [80, 172], [96, 176], [94, 160], [88, 140], [85, 122], [82, 112]]],
    teres: [[[67, 94], [60, 98], [58, 106], [64, 111], [72, 106]]],
    delt_rear: [[[66, 77], [59, 72], [54, 78], [54, 92], [58, 102], [65, 98], [67, 88]]],
    delt_side: [[[53, 78], [48, 74], [43, 80], [42, 92], [46, 101], [52, 102], [53, 90]]],
    erectors: [[[99, 152, 1], [91, 152], [87, 168], [88, 190], [93, 204], [99, 206, 1]]],
    triceps_long: [[[52, 90], [57, 100], [56, 120], [49, 136], [45, 130], [47, 110], [49, 96]]],
    triceps_lateral: [[[46, 92], [41, 102], [40, 118], [41, 132], [45, 134], [46, 116], [47, 100]]],
    forearm_extensors: [[[50, 146], [53, 154], [47, 178], [37, 200], [31, 197], [33, 172], [42, 150]]],
    glute_max: [[[100, 206, 1], [86, 206], [74, 208], [66, 216], [66, 230], [76, 242], [90, 242], [100, 238, 1]]],
    abductors: [[[88, 188], [74, 188], [64, 196], [64, 206], [74, 206], [88, 200]]],
    ham_outer: [[[78, 248], [68, 252], [66, 274], [68, 296], [76, 298], [80, 272]]],
    ham_inner: [[[92, 248], [84, 246], [80, 272], [81, 298], [89, 298], [94, 274]]],
    gastrocnemius: [
      [[76, 316], [68, 324], [68, 346], [74, 360], [80, 352], [80, 326]],
      [[92, 316], [84, 320], [84, 350], [88, 362], [94, 350], [96, 326]],
    ],
    soleus: [[[80, 364], [85, 365], [90, 364], [91, 384], [85, 392], [79, 384]]],
  };

  const expandParts = (parts) => {
    const out = {};
    for (const [part, shapes] of Object.entries(parts)) out[part] = shapes.flatMap(bothHalves);
    return out;
  };

  const FIGURE = {
    width: WIDTH,
    height: HEIGHT,
    base: BASE.flatMap(bothHalves),
    front: expandParts(FRONT),
    back: expandParts(BACK),
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = FIGURE;
  else root.ANATOMY_FIGURE = FIGURE;
})(typeof window !== 'undefined' ? window : globalThis);
