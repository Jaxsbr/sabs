---
name: frontend-design
description: "Design-time guidance for creating distinctive, production-grade frontend interfaces — referenced by the build-loop during UI tasks"
user-invocable: false
---

<!-- version: 1 -->
Design-time guidance for creating distinctive, production-grade frontend interfaces. Referenced by the build-loop during UI implementation tasks. Can also be invoked standalone for design direction.

Based on Anthropic's `claude-code` frontend-design plugin.

---

## Core Principle

Build real working code with exceptional attention to aesthetic details and creative choices. Avoid generic "AI slop" aesthetics.

## Design Thinking

Before coding UI, understand the context and commit to a **bold aesthetic direction**:
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick a clear direction: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian, etc. Use these for inspiration but design one that is true to the project's identity.
- **Constraints**: Technical requirements (framework, performance, accessibility).
- **Differentiation**: What makes this UNFORGETTABLE? What's the one thing someone will remember?

**CRITICAL**: Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism both work — the key is intentionality, not intensity.

## Frontend Aesthetics Guidelines

Focus on:
- **Typography**: Choose fonts that are beautiful, unique, and interesting. Avoid generic fonts like Arial, Inter, and Roboto; opt for distinctive choices that elevate the frontend's aesthetics — unexpected, characterful font choices. Pair a distinctive display font with a refined body font.
- **Color & Theme**: Commit to a cohesive aesthetic. Use CSS variables for consistency. Dominant colors with sharp accents outperform timid, evenly-distributed palettes.
- **Motion**: Use animations for effects and micro-interactions. Prioritize CSS-only solutions for HTML. Use Motion library for React when available. Focus on high-impact moments: one well-orchestrated page load with staggered reveals creates more delight than scattered micro-interactions. Use scroll-triggering and hover states that surprise.
- **Spatial Composition**: Unexpected layouts. Asymmetry. Overlap. Diagonal flow. Grid-breaking elements. Generous negative space OR controlled density.
- **Backgrounds & Visual Details**: Create atmosphere and depth rather than defaulting to solid colors. Add contextual effects and textures that match the overall aesthetic. Apply creative forms like gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, and grain overlays.

## Anti-patterns (never do these)

- Overused font families (Inter, Roboto, Arial, system-ui as the only font)
- Cliched color schemes (purple gradients on white backgrounds)
- Predictable layouts and component patterns
- Cookie-cutter design that lacks context-specific character
- Converging on the same "safe" choices across projects (e.g., always using Space Grotesk)

## Implementation Notes

- Match implementation complexity to the aesthetic vision. Maximalist designs need elaborate code with extensive animations. Minimalist designs need restraint, precision, and careful spacing/typography.
- Vary between light and dark themes, different fonts, different aesthetics across projects.
- Interpret creatively and make unexpected choices that feel genuinely designed for the context.
