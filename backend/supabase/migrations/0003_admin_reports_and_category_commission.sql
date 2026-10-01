-- Allow admins to read incoming reports
drop policy if exists "reports_read_admin_only" on public.reports;
create policy "reports_read_admin_only" on public.reports
for select using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

-- Seed per-category commission settings for admin updates
insert into public.app_settings(key, value)
values (
  'commission_rate_by_category',
  '{
    "plumbing": 0.075,
    "electrician": 0.075,
    "ac_repair": 0.075,
    "carpenter": 0.075,
    "painter": 0.075,
    "cleaning": 0.075,
    "appliance_repair": 0.075,
    "registered_nurse": 0.075
  }'::jsonb
)
on conflict (key) do nothing;
