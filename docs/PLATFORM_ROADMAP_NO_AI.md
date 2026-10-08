# OTO TAG platform modernization

Scope excludes the AI vehicle assistant (fault code explanation, symptom diagnosis, cost inference, or AI provider recommendations).

## Release gates
1. Keep live production untouched while work proceeds on feature/platform-hardening-phase1.
2. CI must pass flutter analyze, flutter test and PHP syntax before merge. Integration suites requiring MySQL run on a dedicated staging database.
3. Security: immediately rotate any real keys previously committed (especially Apple .p8, API credentials and environment secrets); removing files from latest git commit does not revoke them or erase Git history. Review repository history and public exposure before deciding on history rewrite.
4. Validate role access (customer/provider/rentacar/admin) server-side, including object ownership checks, rate limits and audit logs.
5. Require genuine provider identity and live availability for actionable offers. Fallback estimates must clearly be marked as estimates and never bookable.
6. Confirm matching invariants in integration tests: same normalized city, matching service, distance within radius, subscription active, not suspended, not busy, at most one accepted offer.
7. Rental: overlapping dates must be blocked transactionally, listing availability verified on booking, counter-offers and cancellation outcomes covered by tests.
8. User experience: four primary bottom navigation destinations; service categories in a secondary grid; progressive disclosure for vehicle management.
9. Growth instrumentation: track attribution, signup, verified account, quote submitted, quote accepted, completed job, cancellation and subscription conversion. Store event counts without unneeded personal details.
10. Performance: measure first frame, API p95, SQL slow queries, network timeouts, list pagination, background timer disposal and cache invalidation.

## Suggested implementation increments
- P0: rotate exposed credentials outside GitHub, confirm staging and rollback, enforce CI and instrument errors.
- P1: matching server invariants and real-only offers with status feedback, rental concurrency tests.
- P2: reusable navigation and UI tokens for customer, provider and rental dashboards, extract the customer dashboard into widgets/services.
- P3: vehicle reminders, verified rental booking, growth analytics, conversion funnels and subscriptions.
- P4: load tests and deployment runbook. Ship each increment independently after regression verification.

## Local verification
```powershell
flutter pub get
flutter analyze
flutter test
git status
```

Before pulling: if MERGE_HEAD exists, resolve and commit/abort intentionally; save uncommitted local work. Never run git reset --hard to fix a merge without backup.
