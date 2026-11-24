-- Mention personnalisée imprimée en bas des tickets (voyage et colis), choisie par l'administrateur.
alter table public.company_settings add column if not exists mention_ticket text not null default '';
alter table public.company_settings drop constraint if exists company_settings_mention_ticket_check;
alter table public.company_settings add constraint company_settings_mention_ticket_check check (char_length(mention_ticket) <= 160);
