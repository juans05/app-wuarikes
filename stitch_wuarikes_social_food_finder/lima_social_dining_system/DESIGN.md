---
name: Lima Social Dining System
colors:
  surface: '#f9f9f9'
  surface-dim: '#dadada'
  surface-bright: '#f9f9f9'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f3f3'
  surface-container: '#eeeeee'
  surface-container-high: '#e8e8e8'
  surface-container-highest: '#e2e2e2'
  on-surface: '#1a1c1c'
  on-surface-variant: '#4a4453'
  inverse-surface: '#2f3131'
  inverse-on-surface: '#f0f1f1'
  outline: '#7b7484'
  outline-variant: '#ccc3d5'
  surface-tint: '#6f43c0'
  primary: '#4f1c9e'
  on-primary: '#ffffff'
  primary-container: '#673ab7'
  on-primary-container: '#d8c2ff'
  inverse-primary: '#d3bbff'
  secondary: '#605d69'
  on-secondary: '#ffffff'
  secondary-container: '#e6e0ef'
  on-secondary-container: '#66636f'
  tertiary: '#523c00'
  on-tertiary: '#ffffff'
  tertiary-container: '#6e5200'
  on-tertiary-container: '#ffc320'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ebddff'
  primary-fixed-dim: '#d3bbff'
  on-primary-fixed: '#250059'
  on-primary-fixed-variant: '#5727a6'
  secondary-fixed: '#e6e0ef'
  secondary-fixed-dim: '#c9c4d3'
  on-secondary-fixed: '#1c1a25'
  on-secondary-fixed-variant: '#484551'
  tertiary-fixed: '#ffdf9e'
  tertiary-fixed-dim: '#fabd00'
  on-tertiary-fixed: '#261a00'
  on-tertiary-fixed-variant: '#5b4300'
  background: '#f9f9f9'
  on-background: '#1a1c1c'
  surface-variant: '#e2e2e2'
typography:
  display-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -1px
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
  title-lg:
    fontFamily: Be Vietnam Pro
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Be Vietnam Pro
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Be Vietnam Pro
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-md:
    fontFamily: Be Vietnam Pro
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.5px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  container-margin: 20px
  gutter: 16px
---

## Brand & Style

This design system captures the vibrant, culinary-rich energy of Lima through a modern, structured lens. It targets a youthful, food-obsessed audience that values both social connection and high-quality local discoveries. 

The aesthetic is rooted in **Modern Corporate** efficiency but injected with **High-Contrast** energy. It utilizes a "Flat-Plus" approach: clean, untextured surfaces that rely on vibrant photography and bold typography rather than complex gradients or shadows. The goal is to create a digital canvas that recedes to let the colors of Peruvian ingredients and the excitement of urban exploration take center stage. The emotional response should be one of reliability, local pride, and appetizing clarity.

## Colors

The palette is derived from a Material 3 logic but refined for high-contrast legibility. 

- **Primary:** The Deep Purple (#673AB7) serves as the "Electric Lima" signature, used for brand moments, primary actions, and active navigation states.
- **Surface & Background:** To maintain a "breathable" feel, the app uses an almost-white background (#FAFAFA) while cards and interactive surfaces use pure white (#FFFFFF). 
- **Accent/Rating:** A vivid Amber (#FFC107) is reserved strictly for ratings and "hidden gem" highlights, providing a warm contrast to the cool purple.
- **Borders:** Instead of heavy shadows, structural separation is achieved through a 1px #EEEEEE border on all surface containers.

## Typography

This design system utilizes a dual-sans-serif approach to balance impact with readability. **Plus Jakarta Sans** is used for headlines to provide a modern, slightly rounded geometric feel that aligns with the "youthful energy" requirement. **Be Vietnam Pro** is used for all body text and labels, offering exceptional legibility for menu items and restaurant descriptions.

- **Headlines:** Use soft black (#212121) with tight letter spacing for a punchy, editorial look.
- **Body & Metadata:** Use medium gray (#757575) for secondary information to create a clear visual hierarchy against primary titles.
- **Labels:** Always use medium or bold weights to ensure visibility against the primary purple or light purple background.

## Layout & Spacing

The design system follows a **Fluid Grid** model based on an 8px square rhythm. 

- **Mobile:** 4-column grid with 20px side margins and 16px gutters.
- **Desktop:** 12-column grid with a max-width of 1200px.
- **Vertical Rhythm:** Elements are separated by 16px or 24px increments to maintain a spacious, premium feel. 

Photography should always be edge-to-edge within its parent container, using the large corner radii defined in the Shapes section to maintain the friendly, "bubbly" brand character.

## Elevation & Depth

This design system avoids traditional Material 3 elevation shadows in favor of **Low-Contrast Outlines**. 

- **Level 0 (Background):** #FAFAFA.
- **Level 1 (Cards/Inputs):** #FFFFFF with a 1px solid #EEEEEE border.
- **Active State:** Elements may gain a subtle, tinted shadow using the primary color at 8% opacity to indicate interactivity without introducing "muddy" grays.
- **Map Elements:** Map pins and floating action buttons are the only elements permitted to have a high-contrast shadow (Blur 8, Y-Offset 4, 15% Black) to ensure they pop against complex map textures.

## Shapes

The shape language is "Extra-Rounded" to evoke a friendly, welcoming atmosphere. 

- **Main Containers:** Top-level containers (like Bottom Sheets or full-screen modals) use 24px top-corner rounding.
- **Cards:** All restaurant and social feed cards use a 16px border radius.
- **Interactive Elements:** Buttons and Input fields use 12px or 16px radius to match the card language.
- **Icons:** Use "Rounded" icon variants (Material Symbols Rounded) to harmonize with the typography.

## Components

- **Buttons:** Primary buttons are #673AB7 with white text. Secondary buttons use the #EDE7F6 background with primary purple text. All have a 12px-16px radius.
- **Cards:** White background, 1px #EEEEEE border, 16px radius. Images must have a 16:9 or 1:1 aspect ratio with top corners rounded to match the card.
- **Chips:** Used for cuisine categories (e.g., "Cebichería"). Use #FAFAFA background with #757575 text for inactive, and #673AB7 with white text for active states.
- **Map Pins:** Large, circular avatars of restaurant logos with a #673AB7 border and a bottom pointer.
- **Ratings:** Use the Amber #FFC107 for star icons and the numerical value.
- **Bottom Navigation:** Solid white background with a 1px top border (#EEEEEE). Active icons use primary purple; inactive use medium gray.