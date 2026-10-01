-- Core enums
create type public.user_role as enum ('customer', 'pro', 'admin');
create type public.job_status as enum ('posted', 'available', 'in_process', 'completed', 'paid_closed', 'cancelled', 'disputed');
create type public.bid_status as enum ('pending', 'accepted', 'rejected', 'withdrawn');
create type public.payment_method as enum ('jazzcash', 'easypaisa', 'cash');
create type public.payment_state as enum ('initiated', 'completed', 'failed');

create extension if not exists "pgcrypto";

-- Generic timestamps
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- Profiles
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.user_role not null default 'customer',
  full_name text not null,
  email text not null unique,
  phone text not null,
  profile_image_url text,
  language_code text not null default 'en',
  cnic_verified boolean not null default false,
  police_verified boolean not null default false,
  rating numeric(3,2) not null default 0,
  total_reviews integer not null default 0,
  notifications_enabled boolean not null default true,
  precise_location_enabled boolean not null default false,
  payment_account text,
  blocked boolean not null default false,
  preferred_categories text[] not null default '{}',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

-- Terms acceptance (required before account creation completion)
create table if not exists public.terms_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  terms_version text not null,
  privacy_version text not null,
  accepted_at timestamptz not null,
  ip_address text not null,
  device_info text not null,
  checkbox_confirmed boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_terms_acceptances_user_id on public.terms_acceptances(user_id);

-- User saved locations
create table if not exists public.saved_locations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  label text not null,
  latitude double precision not null,
  longitude double precision not null,
  address text not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_saved_locations_user on public.saved_locations(user_id);

-- Jobs
create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  category text not null,
  title text not null,
  description text not null,
  fixed_price numeric(12,2) not null check (fixed_price > 0),
  latitude double precision not null,
  longitude double precision not null,
  masked_address text not null,
  exact_address text not null,
  status public.job_status not null default 'posted',
  assigned_pro_id uuid references public.profiles(id),
  selected_bid_id uuid,
  final_amount numeric(12,2),
  cancel_reason text,
  dispute_reason text,
  timeline jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_jobs_customer on public.jobs(customer_id);
create index if not exists idx_jobs_assigned_pro on public.jobs(assigned_pro_id);
create index if not exists idx_jobs_status on public.jobs(status);
create index if not exists idx_jobs_category on public.jobs(category);

create trigger jobs_set_updated_at
before update on public.jobs
for each row execute function public.set_updated_at();

-- Bids (accept fixed price or higher counter-bid)
create table if not exists public.bids (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  pro_id uuid not null references public.profiles(id),
  amount numeric(12,2) not null check (amount > 0),
  status public.bid_status not null default 'pending',
  notes text,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_bids_job on public.bids(job_id);
create index if not exists idx_bids_pro on public.bids(pro_id);

-- Payments (online/cash both recorded; app does not hold funds)
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  customer_id uuid not null references public.profiles(id),
  pro_id uuid not null references public.profiles(id),
  method public.payment_method not null,
  state public.payment_state not null default 'initiated',
  gross_amount numeric(12,2) not null check (gross_amount > 0),
  platform_fee numeric(12,2) not null check (platform_fee >= 0),
  net_pro_amount numeric(12,2) not null check (net_pro_amount >= 0),
  external_reference text,
  created_at timestamptz not null default timezone('utc', now()),
  recorded_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_payments_job on public.payments(job_id);
create index if not exists idx_payments_customer on public.payments(customer_id);
create index if not exists idx_payments_pro on public.payments(pro_id);
create index if not exists idx_payments_method on public.payments(method);

-- Chat
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  sender_id uuid not null references public.profiles(id),
  receiver_id uuid not null references public.profiles(id),
  text text not null,
  sent_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_chat_messages_job on public.chat_messages(job_id);
create index if not exists idx_chat_messages_sender on public.chat_messages(sender_id);
create index if not exists idx_chat_messages_receiver on public.chat_messages(receiver_id);

-- Notification events
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  metadata jsonb not null default '{}'::jsonb,
  read boolean not null default false,
  sent_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_notifications_user on public.notifications(user_id);

-- Reports / abuse actions
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id),
  target_user_id uuid not null references public.profiles(id),
  reason text not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_reports_target on public.reports(target_user_id);

-- Platform settings (commission)
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default timezone('utc', now())
);

insert into public.app_settings(key, value)
values ('commission_rate', '0.075'::jsonb)
on conflict (key) do nothing;

-- Full audit trail
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  ip_address text,
  device_info text,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_audit_logs_entity on public.audit_logs(entity_type, entity_id);
create index if not exists idx_audit_logs_actor on public.audit_logs(actor_id);
create index if not exists idx_audit_logs_created on public.audit_logs(created_at desc);

-- Generic audit trigger for key transactional tables
create or replace function public.log_row_change()
returns trigger
language plpgsql
security definer
as $$
declare
  payload jsonb;
  row_id text;
begin
  payload := case
    when tg_op = 'DELETE' then to_jsonb(old)
    else to_jsonb(new)
  end;

  row_id := coalesce(payload->>'id', '');

  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata, created_at)
  values (
    auth.uid(),
    lower(tg_table_name || '_' || tg_op),
    tg_table_name,
    row_id,
    jsonb_build_object('op', tg_op, 'data', payload),
    timezone('utc', now())
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists jobs_audit_trigger on public.jobs;
create trigger jobs_audit_trigger
after insert or update or delete on public.jobs
for each row execute function public.log_row_change();

drop trigger if exists bids_audit_trigger on public.bids;
create trigger bids_audit_trigger
after insert or update or delete on public.bids
for each row execute function public.log_row_change();

drop trigger if exists payments_audit_trigger on public.payments;
create trigger payments_audit_trigger
after insert or update or delete on public.payments
for each row execute function public.log_row_change();

drop trigger if exists chat_messages_audit_trigger on public.chat_messages;
create trigger chat_messages_audit_trigger
after insert or update or delete on public.chat_messages
for each row execute function public.log_row_change();

drop trigger if exists notifications_audit_trigger on public.notifications;
create trigger notifications_audit_trigger
after insert or update or delete on public.notifications
for each row execute function public.log_row_change();

drop trigger if exists terms_acceptances_audit_trigger on public.terms_acceptances;
create trigger terms_acceptances_audit_trigger
after insert or update or delete on public.terms_acceptances
for each row execute function public.log_row_change();

-- RLS
alter table public.profiles enable row level security;
alter table public.terms_acceptances enable row level security;
alter table public.saved_locations enable row level security;
alter table public.jobs enable row level security;
alter table public.bids enable row level security;
alter table public.payments enable row level security;
alter table public.chat_messages enable row level security;
alter table public.notifications enable row level security;
alter table public.reports enable row level security;
alter table public.audit_logs enable row level security;
alter table public.app_settings enable row level security;

create policy "profiles_select_own_or_admin" on public.profiles
for select using (id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy "profiles_update_own_or_admin" on public.profiles
for update using (id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy "terms_select_own_or_admin" on public.terms_acceptances
for select using (user_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy "terms_insert_own" on public.terms_acceptances
for insert with check (user_id = auth.uid());

create policy "saved_locations_own" on public.saved_locations
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "jobs_read_related_or_admin" on public.jobs
for select using (
  customer_id = auth.uid()
  or assigned_pro_id = auth.uid()
  or status in ('posted', 'available')
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "jobs_insert_customer" on public.jobs
for insert with check (customer_id = auth.uid());

create policy "jobs_update_related_or_admin" on public.jobs
for update using (
  customer_id = auth.uid()
  or assigned_pro_id = auth.uid()
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "bids_read_related_or_admin" on public.bids
for select using (
  pro_id = auth.uid()
  or exists (select 1 from public.jobs j where j.id = job_id and j.customer_id = auth.uid())
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "bids_insert_pro" on public.bids
for insert with check (pro_id = auth.uid());

create policy "payments_read_related_or_admin" on public.payments
for select using (
  customer_id = auth.uid()
  or pro_id = auth.uid()
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "payments_insert_customer_or_admin" on public.payments
for insert with check (
  customer_id = auth.uid()
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "chat_read_related_or_admin" on public.chat_messages
for select using (
  sender_id = auth.uid()
  or receiver_id = auth.uid()
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "chat_insert_sender" on public.chat_messages
for insert with check (sender_id = auth.uid());

create policy "notifications_own_or_admin" on public.notifications
for all using (
  user_id = auth.uid()
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
) with check (
  user_id = auth.uid()
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "reports_insert_authenticated" on public.reports
for insert with check (reporter_id = auth.uid());

create policy "audit_read_admin_only" on public.audit_logs
for select using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy "audit_insert_system_or_admin" on public.audit_logs
for insert with check (auth.uid() is not null);

create policy "settings_read_authenticated" on public.app_settings
for select using (auth.uid() is not null);

create policy "settings_update_admin_only" on public.app_settings
for update using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
