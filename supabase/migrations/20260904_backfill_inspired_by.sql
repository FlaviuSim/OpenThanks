-- Best-effort historical ripple attribution.
-- Heuristic: if someone sent a thanks within 48 hours of accepting one,
-- link their send to the most recently accepted parent appreciation.
-- Not perfect — only new pay-it-forward flows set this exactly going forward.

WITH candidates AS (
  SELECT
    child.id AS child_id,
    parent.id AS parent_id,
    row_number() OVER (
      PARTITION BY child.id
      ORDER BY parent.accepted_at DESC NULLS LAST, parent.created_at DESC
    ) AS rn
  FROM public.gratitudes child
  JOIN public.gratitudes parent
    ON parent.recipient_id = child.author_id
   AND parent.status = 'accepted'
   AND parent.accepted_at IS NOT NULL
   AND parent.accepted_at <= child.created_at
   AND parent.accepted_at >= child.created_at - interval '48 hours'
   AND parent.id <> child.id
   AND parent.author_id IS DISTINCT FROM child.author_id
  WHERE child.inspired_by_gratitude_id IS NULL
    AND child.author_id IS NOT NULL
)
UPDATE public.gratitudes g
SET inspired_by_gratitude_id = c.parent_id
FROM candidates c
WHERE g.id = c.child_id
  AND c.rn = 1
  AND g.inspired_by_gratitude_id IS NULL;
