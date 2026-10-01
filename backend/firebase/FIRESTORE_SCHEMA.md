# Firestore Schema (Production-Oriented)

This app now persists operational + financial data in dedicated collections for maintainability and fast reporting.

## Collections

### `profiles/{userId}`
- Core user profile:
  - `id`, `username`, `full_name`, `email`, `phone`
  - `role` (`customer` | `pro` | `admin`)
  - `profile_image_url`, `rating`, `total_reviews`
  - `preferred_categories`, `payment_account`
  - `is_online`, `last_seen_at`, `last_active_at`
  - admin fields, verification fields, status flags

### `presence/{userId}`
- Lightweight live presence document:
  - `user_id`
  - `is_online`
  - `last_seen_at`
  - `last_active_at`
  - `updated_at`

### `jobs/{jobId}`
- Job lifecycle + assignment + timeline.

### `bids/{bidId}`
- Pro bids per job.

### `payments/{paymentId}`
- Transaction history:
  - `gross_amount`, `platform_fee`, `net_pro_amount`
  - `method`, `state`, `recorded_at`
  - `customer_id`, `pro_id`, `job_id`

### `financial_ledger/{eventId}`
- Immutable finance event stream (append-only pattern):
  - `type` (`payment_recorded` / `pro_due_settled`)
  - `actor_id`, `job_id`, `payment_id`, `pro_id`, `customer_id`
  - amounts (`gross_amount`, `platform_fee`, `net_pro_amount`, `amount`, `estimated_profit`)
  - `day_key`, `month_key`, timestamps

### `financial_summary/{docId}`
- Aggregated rollups for fast dashboards:
  - `overall`
  - `day_YYYY-MM-DD`
  - `month_YYYY-MM`
- Tracks:
  - `total_gross_revenue`
  - `total_platform_revenue`
  - `total_pro_payout`
  - `total_due_settled`
  - `total_estimated_profit`
  - `payments_count`, `settlements_count`
  - `last_event_at`, `updated_at`

### `chat_messages/{messageId}`
- Message records + read/delete markers.

### `notifications/{notificationId}`
- User notifications.

### `audit_logs/{auditId}`
- App activity trail for moderation/compliance.
- Authentication actions are recorded per user as `login`, `logout`, and
  `session_resumed`, with the event time, app session ID, authentication method,
  and platform/device version. Authentication events do not include passwords,
  tokens, or network IP addresses.

### `reports/{reportId}`
- Abuse reports and safety workflow inputs.

### `app_settings/{settingId}`
- Config (commission rates, etc.).

## Recommended Query Pattern

- Keep user-facing queries scoped by foreign keys:
  - `payments` by `customer_id` / `pro_id`
  - `chat_messages` by `job_id`
  - `notifications` by `user_id`
  - `jobs` by `customer_id` / `assigned_pro_id`
- Use `financial_summary` for admin dashboard totals instead of scanning all `payments`.

## Security Model (Current)

- Role/ownership-based access controls are enforced per collection (customer/pro/admin).
- A signed-in customer may upgrade their own account to a professional account
  only by setting at least one service category; clients cannot promote accounts
  to admin or change verification/blocking fields.
- Profile updates now separate normal self-edits from audited system updates (`_security_update` context).
- Chat, bids, payments, and notifications are constrained by job-participant relationships.
- Reports and audit logs are no longer globally readable by authenticated users.
- Financial ledger remains actor-authenticated on create and admin-readable.
