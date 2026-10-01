drop policy if exists "chat_read_related_or_admin" on public.chat_messages;
create policy "chat_read_assigned_job_participants_or_admin"
on public.chat_messages
for select using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
  or exists (
    select 1
    from public.jobs j
    where j.id = chat_messages.job_id
      and j.assigned_pro_id is not null
      and j.status in ('in_process', 'completed', 'paid_closed', 'disputed')
      and (
        (
          j.customer_id = auth.uid()
          and chat_messages.sender_id = j.assigned_pro_id
          and chat_messages.receiver_id = j.customer_id
        )
        or (
          j.assigned_pro_id = auth.uid()
          and chat_messages.sender_id = j.customer_id
          and chat_messages.receiver_id = j.assigned_pro_id
        )
      )
  )
);

drop policy if exists "chat_insert_sender" on public.chat_messages;
create policy "chat_insert_assigned_job_participant"
on public.chat_messages
for insert with check (
  sender_id = auth.uid()
  and exists (
    select 1
    from public.jobs j
    where j.id = chat_messages.job_id
      and j.assigned_pro_id is not null
      and j.status in ('in_process', 'completed', 'paid_closed', 'disputed')
      and (
        (
          j.customer_id = auth.uid()
          and chat_messages.receiver_id = j.assigned_pro_id
        )
        or (
          j.assigned_pro_id = auth.uid()
          and chat_messages.receiver_id = j.customer_id
        )
      )
  )
);

drop policy if exists "chat_update_participants" on public.chat_messages;
create policy "chat_update_assigned_job_participants"
on public.chat_messages
for update using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
  or exists (
    select 1
    from public.jobs j
    where j.id = chat_messages.job_id
      and j.assigned_pro_id is not null
      and j.status in ('in_process', 'completed', 'paid_closed', 'disputed')
      and (
        (
          j.customer_id = auth.uid()
          and chat_messages.sender_id = j.customer_id
          and chat_messages.receiver_id = j.assigned_pro_id
        )
        or (
          j.assigned_pro_id = auth.uid()
          and chat_messages.sender_id = j.assigned_pro_id
          and chat_messages.receiver_id = j.customer_id
        )
      )
  )
) with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
  or exists (
    select 1
    from public.jobs j
    where j.id = chat_messages.job_id
      and j.assigned_pro_id is not null
      and j.status in ('in_process', 'completed', 'paid_closed', 'disputed')
      and (
        (
          j.customer_id = auth.uid()
          and chat_messages.sender_id = j.customer_id
          and chat_messages.receiver_id = j.assigned_pro_id
        )
        or (
          j.assigned_pro_id = auth.uid()
          and chat_messages.sender_id = j.assigned_pro_id
          and chat_messages.receiver_id = j.customer_id
        )
      )
  )
);

drop policy if exists "audit_insert_system_or_admin" on public.audit_logs;
create policy "audit_insert_actor_or_admin"
on public.audit_logs
for insert with check (
  actor_id = auth.uid()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);
