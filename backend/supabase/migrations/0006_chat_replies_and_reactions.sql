-- Chat reply metadata and emoji reactions.
alter table public.chat_messages
  add column if not exists reply_to_message_id uuid references public.chat_messages(id) on delete set null,
  add column if not exists reply_to_sender_id uuid references public.profiles(id),
  add column if not exists reply_to_sender_name text,
  add column if not exists reply_to_text text,
  add column if not exists reactions jsonb not null default '{}'::jsonb;

create index if not exists idx_chat_messages_reply_to on public.chat_messages(reply_to_message_id);
