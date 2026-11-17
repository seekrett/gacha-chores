-- Chore Capsule: online accountability partners.
-- Paste this whole file into Supabase → SQL Editor → New query, and press Run.
-- Safe to run again: it only creates what's missing and replaces the functions and policies.

-- ─── Profiles: one per phone (anonymous sign-in) ──────────────────────────────

create or replace function public.new_invite_code() returns text
language sql volatile as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
  from generate_series(1, 6);
$$;

create table if not exists public.profiles (
  id           uuid primary key references auth.users on delete cascade,
  display_name text not null default '',
  invite_code  text not null unique default public.new_invite_code(),
  created_at   timestamptz not null default now()
);

-- user_id does the chores; partner_id checks them. One row per direction, not exclusive.
create table if not exists public.partnerships (
  user_id    uuid not null references public.profiles on delete cascade,
  partner_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, partner_id),
  check (user_id <> partner_id)
);

-- Chores a partner assigns. The id is the chore's id in the app.
create table if not exists public.assigned_chores (
  id         uuid primary key,
  user_id    uuid not null references public.profiles on delete cascade,
  partner_id uuid not null references public.profiles on delete cascade,
  chore      jsonb not null,
  deleted    boolean not null default false,
  updated_at timestamptz not null default now()
);

-- Proof waiting for a partner. The id is the submission's id in the app.
create table if not exists public.reviews (
  id            uuid primary key,
  user_id       uuid not null references public.profiles on delete cascade,
  chore_id      uuid not null,
  chore_title   text not null,
  chore_emoji   text not null default '',
  note          text not null default '',
  ai_note       text,
  ai_verified   boolean,
  points        int not null,
  breakdown     jsonb not null,
  photo_paths   text[] not null default '{}',
  submitted_at  timestamptz not null default now(),
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewer_id   uuid references public.profiles on delete set null,
  reviewer_name text,
  comment       text not null default '',
  gold_star     boolean not null default false,
  reviewed_at   timestamptz
);

create table if not exists public.gifts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles on delete cascade,
  from_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  from_name  text not null default '',
  amount     int not null check (amount between 1 and 1000),
  message    text not null default '',
  claimed    boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists reviews_user_status on public.reviews (user_id, status);
create index if not exists assigned_chores_user on public.assigned_chores (user_id);
create index if not exists gifts_user_claimed on public.gifts (user_id, claimed);

-- ─── Helper ──────────────────────────────────────────────────────────────────

-- True when the signed-in phone is a partner of `owner`.
create or replace function public.is_partner_of(owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from partnerships where user_id = owner and partner_id = auth.uid());
$$;

create or replace function public.is_linked_with(other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from partnerships
    where (user_id = other and partner_id = auth.uid()) or (user_id = auth.uid() and partner_id = other)
  );
$$;

-- ─── Row-level security ──────────────────────────────────────────────────────

alter table public.profiles        enable row level security;
alter table public.partnerships    enable row level security;
alter table public.assigned_chores enable row level security;
alter table public.reviews         enable row level security;
alter table public.gifts           enable row level security;

drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_linked_with(id));
drop policy if exists "profiles insert own" on public.profiles;
create policy "profiles insert own" on public.profiles for insert to authenticated
  with check (id = auth.uid());
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "partnerships read" on public.partnerships;
create policy "partnerships read" on public.partnerships for select to authenticated
  using (user_id = auth.uid() or partner_id = auth.uid());
-- Either side can end a partnership. New ones are only made through join_as_partner().
drop policy if exists "partnerships delete" on public.partnerships;
create policy "partnerships delete" on public.partnerships for delete to authenticated
  using (user_id = auth.uid() or partner_id = auth.uid());

drop policy if exists "assigned read" on public.assigned_chores;
create policy "assigned read" on public.assigned_chores for select to authenticated
  using (user_id = auth.uid() or partner_id = auth.uid());
drop policy if exists "assigned insert" on public.assigned_chores;
create policy "assigned insert" on public.assigned_chores for insert to authenticated
  with check (partner_id = auth.uid() and public.is_partner_of(user_id));
drop policy if exists "assigned update" on public.assigned_chores;
create policy "assigned update" on public.assigned_chores for update to authenticated
  using (partner_id = auth.uid())
  with check (partner_id = auth.uid() and public.is_partner_of(user_id));

drop policy if exists "reviews read" on public.reviews;
create policy "reviews read" on public.reviews for select to authenticated
  using (user_id = auth.uid() or public.is_partner_of(user_id));
drop policy if exists "reviews insert own" on public.reviews;
create policy "reviews insert own" on public.reviews for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending' and reviewer_id is null);
drop policy if exists "reviews delete own" on public.reviews;
create policy "reviews delete own" on public.reviews for delete to authenticated
  using (user_id = auth.uid());
-- No update policy: only decide_review() can approve or reject.

drop policy if exists "gifts read" on public.gifts;
create policy "gifts read" on public.gifts for select to authenticated
  using (user_id = auth.uid() or from_id = auth.uid());
drop policy if exists "gifts send" on public.gifts;
create policy "gifts send" on public.gifts for insert to authenticated
  with check (from_id = auth.uid() and claimed = false and public.is_partner_of(user_id));
drop policy if exists "gifts claim" on public.gifts;
create policy "gifts claim" on public.gifts for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and claimed = true);

-- ─── Actions ─────────────────────────────────────────────────────────────────

-- Become the partner of whoever owns `code`.
create or replace function public.join_as_partner(code text) returns json
language plpgsql security definer set search_path = public as $$
declare
  owner profiles;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  select * into owner from profiles where invite_code = upper(trim(code));
  if owner.id is null then raise exception 'No one has that invite code. Check it and try again.'; end if;
  if owner.id = auth.uid() then raise exception 'That''s your own invite code. Enter a friend''s code instead.'; end if;
  insert into partnerships (user_id, partner_id) values (owner.id, auth.uid()) on conflict do nothing;
  return json_build_object('id', owner.id, 'display_name', owner.display_name);
end $$;

-- Approve or send back proof. Only a current partner of its owner, and only once.
create or replace function public.decide_review(p_review_id uuid, p_approve boolean, p_comment text, p_gold_star boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update reviews r set
    status        = case when p_approve then 'approved' else 'rejected' end,
    reviewer_id   = auth.uid(),
    reviewer_name = (select display_name from profiles where id = auth.uid()),
    comment       = coalesce(p_comment, ''),
    gold_star     = p_approve and coalesce(p_gold_star, false),
    reviewed_at   = now()
  where r.id = p_review_id
    and r.status = 'pending'
    and exists (select 1 from partnerships p where p.user_id = r.user_id and p.partner_id = auth.uid());
  if not found then
    raise exception 'This proof was already reviewed, or you are no longer their partner.';
  end if;
end $$;

revoke execute on function public.join_as_partner(text) from anon;
revoke execute on function public.decide_review(uuid, boolean, text, boolean) from anon;

-- ─── Photo storage ───────────────────────────────────────────────────────────
-- Private bucket. Photos live at <owner id>/<submission id>/<n>.jpg.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('proofs', 'proofs', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

drop policy if exists "proofs upload own" on storage.objects;
create policy "proofs upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'proofs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "proofs update own" on storage.objects;
create policy "proofs update own" on storage.objects for update to authenticated
  using (bucket_id = 'proofs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "proofs delete own" on storage.objects;
create policy "proofs delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'proofs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "proofs read own or partner" on storage.objects;
create policy "proofs read own or partner" on storage.objects for select to authenticated
  using (
    bucket_id = 'proofs'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1 from public.partnerships p
        where p.user_id::text = (storage.foldername(name))[1] and p.partner_id = auth.uid()
      )
    )
  );
