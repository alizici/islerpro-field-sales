-- =============================================================================
-- 0037 · K44 · Aydınlatma onayını ÖĞRETMEN de verebilmeli
--
-- Hata: aktif öğretmen uygulamaya HİÇ GİREMİYORDU.
--
--   K3 · Öğretmen işletmenin ÜYESİ DEĞİLDİR; kuruma bağlanır. Bu yüzden
--   `memberships` satırı yoktur ve istemcideki `Session.tenantId` null kalır.
--   KVKK ekranındaki "Onaylıyorum" düğmesi tenant istiyordu, yani öğretmen
--   için hiçbir zaman aktifleşmiyordu: ekranda tek çalışan düğme "Çıkış yap".
--
--   Yönlendirme onu oraya doğru getiriyordu (kurulum bitti, onay eksik), ama
--   çıkışı yoktu. Rolün tamamı kapalıydı.
--
-- Karar: **onayı hangi işletmeye yazacağını istemci bilmek zorunda değil.**
-- Onay kişiseldir (`consent_ok` yalnızca kullanıcıya bakar); `tenant_id` bir
-- kayıt alanıdır, bir izin sorusu değil. Sunucu kendisi çözüyor.
-- =============================================================================
create or replace function record_consent(
  p_tenant_id uuid default null,
  p_surum text default 'v1'
) returns void
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid;
begin
  v_tenant := coalesce(
    -- İstemci bir şey söylediyse ve gerçekten oraya bağlıysa ona yazılır.
    (select p_tenant_id where p_tenant_id in (select auth_tenant_ids())),
    -- İşletme tarafı: kendi işletmesi.
    (select tenant_id from memberships
      where user_id = auth.uid() and status = 'aktif' limit 1),
    -- Öğretmen · kendisine cari açılmışsa o dükkanın işletmesi.
    (select a.tenant_id from accounts a where a.user_id = auth.uid() limit 1),
    -- Öğretmen · daveti hangi dükkandan geldiyse onun işletmesi.
    (select s.tenant_id from invites i join stores s on s.id = i.store_id
      where i.kullanan_user_id = auth.uid()
      order by i.kullanildi_at desc nulls last limit 1),
    -- Öğretmen · kurumuyla iş yapan dükkanın işletmesi.
    (select s.tenant_id
       from institution_memberships im
       join accounts a on a.institution_id = im.institution_id
       join stores s on s.id = a.store_id
      where im.user_id = auth.uid() and im.status = 'aktif' limit 1));

  if v_tenant is null then
    -- Sessizce geçmiyoruz: onay kaydedilemediyse kullanıcı ekranda kalır ve
    -- SEBEBİNİ bilmelidir.
    raise exception 'Onay kaydedilemedi: hesabınız henüz bir işletmeye '
                    'bağlı değil. Davet kodunuzu kullandığınızdan emin olun.';
  end if;

  insert into consents (user_id, tenant_id, metin_surum)
  values (auth.uid(), v_tenant, p_surum)
  on conflict (user_id, tenant_id, metin_surum) do nothing;
end $$;

grant execute on function record_consent(uuid, text) to authenticated;
