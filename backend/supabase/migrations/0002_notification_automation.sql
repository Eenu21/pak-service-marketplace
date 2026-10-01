create or replace function public.geo_distance_km(
  lat1 double precision,
  lon1 double precision,
  lat2 double precision,
  lon2 double precision
)
returns double precision
language sql
immutable
as $$
  select 6371 * acos(
    least(
      1.0,
      cos(radians(lat1)) * cos(radians(lat2)) * cos(radians(lon2) - radians(lon1))
      + sin(radians(lat1)) * sin(radians(lat2))
    )
  );
$$;

create or replace function public.notify_pros_on_job_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications(id, user_id, type, title, body, metadata, read, sent_at)
  select
    gen_random_uuid(),
    p.id,
    'job_nearby',
    'New ' || replace(new.category, '_', ' ') || ' job',
    'Fixed price: PKR ' || trim(to_char(new.fixed_price, 'FM999999990.00')),
    jsonb_build_object('job_id', new.id),
    false,
    timezone('utc', now())
  from public.profiles p
  left join lateral (
    select sl.latitude, sl.longitude
    from public.saved_locations sl
    where sl.user_id = p.id
    order by sl.created_at desc
    limit 1
  ) last_loc on true
  where
    p.role = 'pro'
    and p.blocked = false
    and p.cnic_verified = true
    and new.category = any(coalesce(p.preferred_categories, '{}'::text[]))
    and (
      last_loc.latitude is null
      or public.geo_distance_km(last_loc.latitude, last_loc.longitude, new.latitude, new.longitude) <= 25
    );

  return new;
end;
$$;

create or replace function public.notify_customer_on_new_bid()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
begin
  select j.customer_id into v_customer_id
  from public.jobs j
  where j.id = new.job_id;

  if v_customer_id is null then
    return new;
  end if;

  insert into public.notifications(id, user_id, type, title, body, metadata, read, sent_at)
  values (
    gen_random_uuid(),
    v_customer_id,
    'bid_received',
    'New bid',
    'PKR ' || trim(to_char(new.amount, 'FM999999990.00')) || ' by a professional',
    jsonb_build_object('job_id', new.job_id, 'bid_id', new.id),
    false,
    timezone('utc', now())
  );

  return new;
end;
$$;

create or replace function public.notify_pro_on_bid_accepted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_title text;
begin
  if new.status <> 'accepted'::public.bid_status or old.status = new.status then
    return new;
  end if;

  select j.title into v_job_title
  from public.jobs j
  where j.id = new.job_id;

  insert into public.notifications(id, user_id, type, title, body, metadata, read, sent_at)
  values (
    gen_random_uuid(),
    new.pro_id,
    'job_awarded',
    'Job assigned',
    coalesce(v_job_title, 'A job has been assigned to you'),
    jsonb_build_object('job_id', new.job_id, 'bid_id', new.id),
    false,
    timezone('utc', now())
  );

  return new;
end;
$$;

create or replace function public.notify_receiver_on_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications(id, user_id, type, title, body, metadata, read, sent_at)
  values (
    gen_random_uuid(),
    new.receiver_id,
    'message',
    'New message',
    new.text,
    jsonb_build_object('job_id', new.job_id),
    false,
    timezone('utc', now())
  );

  return new;
end;
$$;

create or replace function public.notify_on_job_status_updates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if new.customer_id is not null and new.status in ('in_process', 'completed', 'paid_closed') then
    insert into public.notifications(id, user_id, type, title, body, metadata, read, sent_at)
    values (
      gen_random_uuid(),
      new.customer_id,
      'job_status_update',
      case new.status
        when 'in_process' then 'Job in progress'
        when 'completed' then 'Job marked completed'
        else 'Job closed'
      end,
      new.title,
      jsonb_build_object('job_id', new.id, 'status', new.status),
      false,
      timezone('utc', now())
    );
  end if;

  if new.status = 'paid_closed' and new.assigned_pro_id is not null then
    insert into public.notifications(id, user_id, type, title, body, metadata, read, sent_at)
    values (
      gen_random_uuid(),
      new.assigned_pro_id,
      'payment_received',
      'Payment recorded',
      new.title,
      jsonb_build_object('job_id', new.id),
      false,
      timezone('utc', now())
    );
  end if;

  return new;
end;
$$;

drop trigger if exists jobs_notify_on_insert on public.jobs;
create trigger jobs_notify_on_insert
after insert on public.jobs
for each row execute function public.notify_pros_on_job_post();

drop trigger if exists bids_notify_on_insert on public.bids;
create trigger bids_notify_on_insert
after insert on public.bids
for each row execute function public.notify_customer_on_new_bid();

drop trigger if exists bids_notify_on_update on public.bids;
create trigger bids_notify_on_update
after update on public.bids
for each row execute function public.notify_pro_on_bid_accepted();

drop trigger if exists chat_notify_on_insert on public.chat_messages;
create trigger chat_notify_on_insert
after insert on public.chat_messages
for each row execute function public.notify_receiver_on_new_message();

drop trigger if exists jobs_notify_on_update on public.jobs;
create trigger jobs_notify_on_update
after update on public.jobs
for each row execute function public.notify_on_job_status_updates();
