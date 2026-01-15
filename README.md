# Future

Future is an iOS-first, AI-powered calendar and planning system designed to help people turn complex goals into calm, adaptable daily structure.

## What It Does
- Uses AI to generate personalized plans, events, and tasks
- Adapts when plans change instead of breaking streaks
- Combines scheduling, journaling, and reflection in one system
- Enforces real subscription logic (no fake Pro states)

## Core Features
- AI goal intake with structured plan generation
- Flexible calendar with editable AI-generated events
- Journaling with forgiving streaks (no punishment)
- Real subscriptions via Stripe (monthly & yearly)
- Server-side token enforcement
- Firebase authentication

## Tech Stack
- iOS: SwiftUI
- Backend: FastAPI (Python)
- AI: Google Gemini (backend-only)
- Auth: Firebase
- Payments: Stripe Checkout + Webhooks
- Database: Firestore

## Project Status
Feature-complete and preparing for TestFlight.

## Notes
This project prioritizes calm UX, real backend enforcement, and long-term maintainability over quick demos or mock behavior.
