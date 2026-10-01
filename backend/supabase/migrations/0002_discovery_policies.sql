-- Allow authenticated users to discover professional profiles while preserving
-- private customer visibility.

drop policy if exists "profiles_select_own_or_admin" on public.profiles;

create policy "profiles_select_own_pro_admin" on public.profiles
for select using (
  id = auth.uid()
  or role = 'pro'
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

create policy "saved_locations_select_pro_discovery" on public.saved_locations
for select using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.profiles pro
    where pro.id = user_id and pro.role = 'pro' and not pro.blocked
  )
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);
