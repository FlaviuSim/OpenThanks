-- Attribution for pay-it-forward / ripple chains.
-- When someone sends a thanks after accepting another, we store the parent appreciation.
alter table public.gratitudes
  add column if not exists inspired_by_gratitude_id uuid
    references public.gratitudes (id)
    on delete set null;

create index if not exists gratitudes_inspired_by_gratitude_id_idx
  on public.gratitudes (inspired_by_gratitude_id)
  where inspired_by_gratitude_id is not null;

comment on column public.gratitudes.inspired_by_gratitude_id is
  'Parent appreciation that inspired this send (pay-it-forward / ripple).';
