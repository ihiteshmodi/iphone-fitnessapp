# Impact map: Muscles worked (anatomy diagram)

## Vision
For any exercise, show a simple body diagram (front and back) with the muscles that exercise trains highlighted, so the lifter knows where to focus while training it.

## Role and goal
| Role | Goal (pain → benefit) |
|---|---|
| Lifter | Pain: remembering from a book (Strength Training Anatomy) or from memory which part of the muscle an exercise hits. Benefit: open an exercise and see the trained muscles highlighted, in the app, while training. |
| Customer | Same person. |
| Developer | Muscle knowledge lives in one catalog plus one rules table with tests, so adding a muscle or a rule is a small change. |

## Capabilities → features
| # | Feature | Notes |
|---|---|---|
| M1 | A **small** "Muscles worked" card on the exercise screen, placed near the bottom, just above "Log sets". It zooms in on the side(s) and area of the body that the exercise mainly trains (framed on the primary muscles), with primary shown fully and secondary lighter, plus the names. | The exercise screen layout (user feedback, see `mockups/anatomy.html`): Do today (weight, aim pill, warm-ups with 75% / 90% labels), best-set bar chart, How to, Muscles worked, Log sets last. The Last session, Aim and History boxes are removed. |
| M2 | Automatic muscles for every exercise from its muscle group and name (for example "Incline" highlights the upper chest) | So all 259 exercises show something without any setup. |
| M3 | Choose muscles yourself: pick the entire region (for example the entire upper back) or specific parts, each as primary or secondary | Saved per exercise; "Reset to automatic" undoes it. |
| M4 | Same editor from the exercise library | Edit any exercise's muscles without opening a workout. |

Out of scope: light mode, colour themes (the user chose to keep the black and green look), 3D or animated figures, per-set muscle tracking.

## Decisions
- The book's illustrations are copyrighted, so the figure is drawn from scratch as simple vector shapes (a stylised diagram, not a medical illustration).
- Stored in the database file (new table `exercise_muscles`, schema version 3) so it travels with the backup. Old databases are upgraded when opened.
- No rows for an exercise means "automatic": the app computes the muscles from the name and group each time. Choosing nothing in the editor equals reset to automatic.
- Muscle catalog (33 parts in 14 regions) lives in code, not in the database, because each part has its drawn shape.

## Open guesses
1. The automatic rules are my reading of common exercise science, not a lookup from a book. The editor exists because some will be wrong.
2. Secondary muscles are only suggested for clear cases (pressing adds front delts and triceps, pulling adds biceps).
3. Parts that are mostly hidden from one side (soleus, rhomboids) are drawn only in the view where they are visible.
