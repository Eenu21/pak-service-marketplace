-- Chat read receipts and delete states.
alter table public.chat_messages
  add column if not exists seen_at timestamptz,
  add column if not exists deleted_for_everyone_at timestamptz,
  add column if not exists deleted_for_everyone_by uuid references public.profiles(id),
  add column if not exists deleted_by_sender_at timestamptz,
  add column if not exists deleted_by_receiver_at timestamptz;

create index if not exists idx_chat_messages_seen_at on public.chat_messages(seen_at);

drop policy if exists "chat_update_participants" on public.chat_messages;
create policy "chat_update_participants" on public.chat_messages
for update using (
  sender_id = auth.uid()
  or receiver_id = auth.uid()
) with check (
  sender_id = auth.uid()
  or receiver_id = auth.uid()
);

drop policy if exists "notifications_insert_message_sender" on public.notifications;
create policy "notifications_insert_message_sender" on public.notifications
for insert with check (
  auth.uid() is not null
  and type = 'message'
  and (metadata->>'sender_id')::uuid = auth.uid()
);
