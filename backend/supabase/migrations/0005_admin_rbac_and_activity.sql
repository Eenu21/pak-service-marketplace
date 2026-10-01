alter table public.profiles
  add column if not exists admin_rank text,
  add column if not exists admin_permissions text[] not null default '{}';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_admin_rank_valid'
  ) then
    alter table public.profiles
      add constraint profiles_admin_rank_valid
      check (
        admin_rank is null
        or admin_rank in (
          'super_admin',
          'operations',
          'support',
          'finance',
          'analyst'
        )
      );
  end if;
end $$;

update public.profiles
set
  admin_rank = coalesce(admin_rank, 'super_admin'),
  admin_permissions = case
    when array_length(admin_permissions, 1) is null then
      array[
        'view_metrics',
        'view_audit_logs',
        'manage_reports',
        'manage_users',
        'manage_pro_verification',
        'manage_commissions',
        'export_data',
        'manage_admin_access'
      ]::text[]
    else admin_permissions
  end
where role = 'admin';
