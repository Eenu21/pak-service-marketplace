alter table if exists public.profiles
  add column if not exists total_earnings numeric(12,2) not null default 0,
  add column if not exists due_to_app numeric(12,2) not null default 0;

do $$
begin
  alter table public.profiles
    add constraint profiles_total_earnings_non_negative
    check (total_earnings >= 0);
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter table public.profiles
    add constraint profiles_due_to_app_non_negative
    check (due_to_app >= 0);
exception
  when duplicate_object then null;
end
$$;
