-- Recipient account phone numbers are private. Older clients copied profiles.phone
-- onto gratitudes.recipient_phone when thanking a member, which then surfaced in
-- the sender's SMS/WhatsApp share UI. Clear those leaked values; keep phones the
-- sender typed themselves (they won't match the member's stored account phone).

UPDATE gratitudes AS g
SET recipient_phone = NULL
FROM profiles AS p
WHERE g.recipient_id = p.id
  AND g.recipient_phone IS NOT NULL
  AND btrim(g.recipient_phone) <> ''
  AND p.phone IS NOT NULL
  AND btrim(p.phone) <> ''
  AND regexp_replace(g.recipient_phone, '[^0-9+]', '', 'g')
      = regexp_replace(p.phone, '[^0-9+]', '', 'g');
