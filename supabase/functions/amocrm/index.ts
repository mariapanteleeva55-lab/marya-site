import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_KEY      = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const AMO_SUBDOMAIN     = Deno.env.get('AMOCRM_SUBDOMAIN')!;   // e.g. "marya"
const AMO_CLIENT_ID     = Deno.env.get('AMOCRM_CLIENT_ID')!;
const AMO_CLIENT_SECRET = Deno.env.get('AMOCRM_CLIENT_SECRET')!;
const AMO_REDIRECT_URI  = Deno.env.get('AMOCRM_REDIRECT_URI')!;

const db = createClient(SUPABASE_URL, SUPABASE_KEY);

// ── Получить актуальный access_token ────────────────────────────────
async function getAccessToken(): Promise<string> {
  const { data, error } = await db.from('amocrm_tokens').select('*').eq('id', 1).single();
  if (error || !data) throw new Error('Токены AmoCRM не найдены в БД. Выполните первичную авторизацию.');

  // Если токен ещё не истёк (с запасом 60 сек) — возвращаем как есть
  const now = Math.floor(Date.now() / 1000);
  if (data.expires_at - now > 60) return data.access_token;

  // Иначе обновляем через refresh_token
  const resp = await fetch(`https://${AMO_SUBDOMAIN}.amocrm.ru/oauth2/access_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id:     AMO_CLIENT_ID,
      client_secret: AMO_CLIENT_SECRET,
      grant_type:    'refresh_token',
      refresh_token: data.refresh_token,
      redirect_uri:  AMO_REDIRECT_URI,
    }),
  });
  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`Ошибка обновления токена AmoCRM: ${resp.status} ${txt}`);
  }
  const tokens = await resp.json();
  const newExpiresAt = now + (tokens.expires_in ?? 86400);

  await db.from('amocrm_tokens').upsert({
    id:            1,
    access_token:  tokens.access_token,
    refresh_token: tokens.refresh_token,
    expires_at:    newExpiresAt,
    updated_at:    new Date().toISOString(),
  });

  return tokens.access_token;
}

// ── Вызов AmoCRM REST API ───────────────────────────────────────────
async function amoApi(method: 'GET' | 'POST' | 'PATCH', path: string, body?: unknown, token?: string) {
  const accessToken = token ?? await getAccessToken();
  const resp = await fetch(`https://${AMO_SUBDOMAIN}.amocrm.ru${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`AmoCRM API error ${resp.status}: ${txt}`);
  }
  if (resp.status === 204) return null;
  return resp.json();
}

// ── Найти или создать контакт ────────────────────────────────────────
async function findOrCreateContact(email: string, phone: string, name: string, token: string): Promise<number | null> {
  // Поиск по email
  if (email) {
    try {
      const found = await amoApi('GET', `/api/v4/contacts?query=${encodeURIComponent(email)}&limit=1`, undefined, token);
      const contacts = found?._embedded?.contacts;
      if (contacts?.length) return contacts[0].id;
    } catch (_) { /* продолжаем — создадим новый */ }
  }

  // Нет данных — не создаём пустой контакт
  if (!email && !phone && !name) return null;

  const fields = [];
  if (email) fields.push({ field_code: 'EMAIL', values: [{ value: email, enum_code: 'WORK' }] });
  if (phone) fields.push({ field_code: 'PHONE', values: [{ value: phone, enum_code: 'WORK' }] });

  const created = await amoApi('POST', '/api/v4/contacts', {
    _embedded: {
      contacts: [{
        name: name || email || phone || 'Покупатель',
        custom_fields_values: fields,
      }],
    },
  }, token);
  return created?._embedded?.contacts?.[0]?.id ?? null;
}

// ── Создать сделку + примечание ──────────────────────────────────────
async function createDeal(payload: {
  orderId: string;
  contactId: number | null;
  total: number;
  items: Array<{ name: string; price: number; qty: number }>;
  delivery: string;
  address: string;
  payMethod: string;
  token: string;
}) {
  const { orderId, contactId, total, items, delivery, address, payMethod, token } = payload;

  const leadBody: Record<string, unknown> = {
    name: `Заказ ${orderId}`,
    price: total,
  };
  if (contactId) {
    leadBody._embedded = { contacts: [{ id: contactId }] };
  }

  const result = await amoApi('POST', '/api/v4/leads', {
    _embedded: { leads: [leadBody] },
  }, token);

  const leadId = result?._embedded?.leads?.[0]?.id;
  if (!leadId) return;

  // Добавляем примечание с деталями заказа
  const deliveryLabels: Record<string, string> = {
    courier: 'Курьер (Челябинск)', 'cdek-courier': 'СДЭК курьер',
    pickup: 'СДЭК ПВЗ', post: 'Почта России', 'office-pickup': 'Самовывоз из офиса',
  };
  const itemsList = items.map(i => `• ${i.name} × ${i.qty} = ${i.price * i.qty} ₽`).join('\n');
  const noteText = [
    `🛒 Заказ: ${orderId}`,
    `💰 Сумма: ${total} ₽`,
    `🚚 Доставка: ${deliveryLabels[delivery] || delivery}`,
    address ? `📍 Адрес: ${address}` : null,
    payMethod ? `💳 Оплата: ${payMethod}` : null,
    itemsList ? `\nСостав:\n${itemsList}` : null,
  ].filter(Boolean).join('\n');

  await amoApi('POST', `/api/v4/leads/${leadId}/notes`, [
    { note_type: 'common', params: { text: noteText } },
  ], token);
}

// ── Первичная авторизация (обмен кода на токены) ────────────────────
async function exchangeCode(code: string) {
  const resp = await fetch(`https://${AMO_SUBDOMAIN}.amocrm.ru/oauth2/access_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id:     AMO_CLIENT_ID,
      client_secret: AMO_CLIENT_SECRET,
      grant_type:    'authorization_code',
      code,
      redirect_uri:  AMO_REDIRECT_URI,
    }),
  });
  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`Ошибка обмена кода: ${resp.status} ${txt}`);
  }
  const tokens = await resp.json();
  const now = Math.floor(Date.now() / 1000);

  await db.from('amocrm_tokens').upsert({
    id:            1,
    access_token:  tokens.access_token,
    refresh_token: tokens.refresh_token,
    expires_at:    now + (tokens.expires_in ?? 86400),
    updated_at:    new Date().toISOString(),
  });

  return { ok: true, expires_in: tokens.expires_in };
}

// ── Main handler ────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });

  try {
    const body = await req.json();
    const { action } = body;

    // Первичная авторизация: POST { action: 'auth', code: '...' }
    if (action === 'auth') {
      const result = await exchangeCode(body.code);
      return new Response(JSON.stringify(result), { headers: { ...cors, 'Content-Type': 'application/json' } });
    }

    // Создать заказ в AmoCRM: POST { action: 'create_order', ... }
    if (action === 'create_order') {
      const { orderId, email, phone, name, total, items, delivery, address, payMethod } = body;
      const token = await getAccessToken();
      const contactId = await findOrCreateContact(email, phone, name, token);
      await createDeal({ orderId, contactId, total, items, delivery, address, payMethod, token });
      return new Response(JSON.stringify({ ok: true }), { headers: { ...cors, 'Content-Type': 'application/json' } });
    }

    return new Response(JSON.stringify({ error: 'Unknown action' }), { status: 400, headers: cors });

  } catch (e) {
    console.error('AmoCRM function error:', e);
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
