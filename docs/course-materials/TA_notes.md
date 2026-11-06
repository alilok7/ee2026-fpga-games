# EE2026 I-FDP: Notes from our Graduate TA

Saved 18 Oct 2026 (week 9). Advice on what makes a project do well or badly.

## 1. Integration is the biggest factor
- The TA said one of the major criteria is **integration between the individual components**: how the parts come together and how much each one contributes to building the overall project.
- **What does badly:** four completely different things that just run side by side and are called "the project". That gets a **very low grade**.
- **What does well:** one product where every member's component depends on, and feeds into, the others.
- For us: the sound engine, key input, game engine and UI/Learn mode all have to work as **one piano game**, not as four separate demos behind a switch.

## 2. Integration is a team job, not one person's role
- **Don't give "integration" to a single member** as their component. The whole team does it together.
- Each member still owns their own component (A/B/C/D) and has to make it fit the shared interfaces.
- Plan regular joint integration sessions from week 10 onwards. Don't leave it to the last week.

## 3. Each component has to involve real work
- Every member's part needs real technical depth and a fair amount of Verilog. A trivial or very thin component will score low.

## 4. Follow the document guidelines exactly
- Use the exact template and format from the manual (GPT-6 proposal, final report, colour coding, word limits, file names).
- Getting the format wrong is an easy way to lose a few marks, so don't.

## 5. Agree on the module interfaces
- Agree as a team on the exact signals passed between modules: key/note number, note on, current mode, score, OLED pixel data, and so on.
- Lock them down early so the four parts plug together cleanly.
- *(My reading of the "API" point. Check with the team.)*

## 6. How to write the progress weeks (GPT-6)
- **Week 9 is now** and week 10 starts next week.
- **Weeks 7–9 (done):** keep these rough and honest.
  - Completing the GPT-5 training tasks is fine to mention. It shows we learned the OLED through the GPTs.
  - Idea discussion, research and rough planning are fine.
  - Don't claim concrete project code we haven't written yet.
- **Weeks 10–12 (to do):** write these as concrete to-do items. Our planned split for these weeks is good.

---

# Project briefing (from the lecture transcript, added 23 Oct 2026)

## 7. What we are actually graded on
- **The four criteria only:** functionality, robustness, UI and UX.
- **Not graded:** complexity and creativity were never mentioned this year. The only complexity that counts is **integration complexity**, meaning how well the four parts are combined.
- What the graders want to see: **"Show us you can program in Verilog quite well."**
- **UX matters a lot.** The A+ example from last semester had a very interactive UI, with windows you could click, drag and use, like on Windows. A pool game lost marks because the mouse controls and physics weren't intuitive.

## 8. Q&A: you must understand your own code
- If the project looks amazing but you can't explain basic things about it, **marks are severely affected, possibly zero for Q&A.** Last semester a student had a very impressive project, couldn't answer basic questions (e.g. about constraints and LEDs) and got zero for that part.
- With an average or simple project, they won't grill you hard.
- **The rule: never build anything you can't explain line by line.**

## 9. Individual grades can differ within a team
- One member can get A+ while another gets B. It depends on each person's component and their Q&A.
- Teams that genuinely work together usually land around A- to A+.
- If you're already doing well in the other EE2026 components, an average project can still get you an A. If not, the project is your chance to pull your grade up.

## 10. Optional devices (audio, VGA)
- Allowed, but **not needed for an A+**.
- More devices usually means less focus and less time. Audio needs some signal processing, and VGA can run you out of resources because it has far more pixels.
- **Never connect two OLEDs on the same side** of the board.

## 11. FPGA resources are a hard limit
- Everyone has 100% of the same Basys3. That is the real limit on what you can build, since AI can generate any feature you want.
- **Optimise to fit more features.** For example, draw shapes with range checks instead of pixel by pixel. A digit can be drawn with at most 3 rectangles.
- **Integrate early and regularly.** 20% + 20% + 20% + 20% doesn't add up to 80% after integration, because it often goes over 100%.

## 12. Using AI and online code
- AI is allowed for the project, roughly **70% your own work and at most about 30% with AI help.**
- **Always state where AI was used** (report Sheet B, with extra pages if needed).
- Using open-source projects as references is fine. Copy-pasting from GitHub or ChatGPT without understanding or citing it is not.
- The graders (one grader plus one moderator) **have seen nearly all past projects**, so a copied project will be recognised.

## 13. GPT-6 proposal
- **Each member writes their own section.** Copy-pasting the same text across members gets no marks.
- Describe what you have done and what you will do. It's basically free marks as long as you write something real.
- You can change the project later. No need to resubmit.

## 14. Final submission and report
- **One bitstream only.**
- **Tentative Canvas dates:** around **7, 9 and 11 November** (project archive, report and peer feedback; check Canvas for the confirmed order).
- **Stick to the word limit.** The report should state clearly what you did, not be an essay. If it's too wordy, the graders may miss components and not give marks for them.
- **Print 2 colour copies** for the week 13 demo.
- Sheet B is course feedback (optional, honest, doesn't affect grades) plus references.

## 15. What past projects scored
| Project | Result | Why |
|---|---|---|
| Tetris | Rarely A- or above | Too common; small tweaks like colour help only a little |
| Snake | Tends to score low | Common, unless changed a lot (e.g. into a different "worm" game) |
| Flappy Bird | Average (~16–20 / 30) | Easy, and code is easy to find online |
| Pool (mouse + physics) | Highly rated but not A | Mouse controls and physics weren't intuitive |
| Random maze generator | One member got A+ | Random generation earned marks. It would have scored more if every maze always had a proper entry and exit |
| Tamagotchi / egg simulator | A- to A if done well | Fun, and the interaction is good |
| Click-and-drag window UI | A+ | Very interactive, high UX |

## 16. What this means for KeyLight
- ✅ **Not a common game** like Tetris, Snake or Flappy Bird, and it's built around interaction (LED guide lights, Learn mode), which is good for UX.
- ✅ **Integration is natural:** every part shares the same keys, sound and screens.
- ⚠️ **The audio Pmod is an optional device** with no provided code, and the TA warned about the extra signal-processing work. Keep the sound engine simple enough to explain fully, and make sure the game is still fun and usable on the visuals and LEDs alone.
- ⚠️ **Every member must be able to explain their own module completely in Q&A.** Use AI to learn and debug, not to write whole modules, and log where it was used.
- ⚠️ **Check resource usage after every integration session.** The falling-note renderer, song ROMs and recording RAM all add up.
- ⚠️ **UX test:** have someone who has never seen it try it with no instructions. If they get stuck, fix the guidance on screen.

## Our current plan (KeyLight piano game)
| Member | Component |
|---|---|
| 1 | Sound engine (audio Pmod, notes, chords, fade-out) |
| 2 | Key input and Free Play (switch flips as keys, on-screen piano, record and playback) |
| 3 | Rhythm game engine (falling notes, Perfect/Good/Miss, score, LED guide lights) |
| 4 | UI and Learn mode (menus, song select, results screen, Learn mode, 7-seg driver) |
| All | **Integration together**, every week from week 10 |
