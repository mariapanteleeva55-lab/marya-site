const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
}

const CDEK_CLIENT_ID     = 'uejYeTXuvgJfQhzbb5cGnU5PZMt1EIah'
const CDEK_CLIENT_SECRET = '8SzS9ttOFDH3oSHasXu6b58bxakZkftf'
const CDEK_API           = 'https://api.cdek.ru'

// ── Получить токен СДЭК ───────────────────────────────────────────
async function getCdekToken(): Promise<string> {
  const params = new URLSearchParams({
    grant_type:    'client_credentials',
    client_id:     CDEK_CLIENT_ID,
    client_secret: CDEK_CLIENT_SECRET,
  })
  const resp = await fetch(`${CDEK_API}/v2/oauth/token`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    params,
  })
  const data = await resp.json()
  return data.access_token
}

// ── Рассчитать вес посылки ────────────────────────────────────────
// Формула: (объём_мл + 200г упаковка) × кол-во
function calcWeight(items: Array<{ volume?: string; qty: number }>): number {
  let total = 0
  for (const item of items) {
    const ml = parseInt(item.volume || '0') || 100  // дефолт 100мл если не указан
    total += (ml + 200) * item.qty
  }
  return Math.max(total, 100) // СДЭК минимум 100г
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url    = new URL(req.url)
    const action = req.method === 'POST'
      ? (await req.clone().json().then((b: Record<string, string>) => b.action).catch(() => null))
      : url.searchParams.get('action')

    // ── Создание заказа СДЭК ─────────────────────────────────────
    if (action === 'create_order') {
      const body = await req.json()
      const { orderId, recipient, deliveryType, pvzCode, address, items } = body

      const token  = await getCdekToken()
      const weight = calcWeight(items || [])

      // Тариф: 138 = дверь→склад (ПВЗ), 139 = дверь→дверь (курьер)
      const tariffCode = deliveryType === 'pickup' ? 138 : 139

      const orderBody: Record<string, unknown> = {
        tariff_code: tariffCode,
        comment:     `Заказ ${orderId}`,
        sender: {
          company: 'Торговый Дом "Фарма"',
          name:    'Бондаренко Ирина Андреевна',
          phones:  [{ number: '+79226974113' }],
        },
        from_location: {
          address: 'г. Челябинск, ул. Блюхера, 59А',
        },
        recipient: {
          name:   recipient.name,
          phones: [{ number: recipient.phone }],
          email:  recipient.email || undefined,
        },
        packages: [{
          number: orderId,
          weight: weight,
          length: 20,
          width:  15,
          height: 10,
          items:  (items || []).map((p: { name: string; price: number; qty: number; volume?: string }) => ({
            name:     p.name,
            ware_key: String(p.name).slice(0, 20),
            payment:  { value: 0 },
            cost:     p.price,
            amount:   p.qty,
            weight:   (parseInt(p.volume || '0') || 100) + 200,
          })),
        }],
      }

      // ПВЗ или курьер — разные поля назначения
      if (deliveryType === 'pickup' && pvzCode) {
        orderBody.delivery_point = pvzCode
      } else {
        orderBody.to_location = { address: address }
      }

      const cdekResp = await fetch(`${CDEK_API}/v2/orders`, {
        method:  'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify(orderBody),
      })

      const result = await cdekResp.json()
      return new Response(JSON.stringify(result), {
        status:  cdekResp.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Прокси GET-запросов к СДЭК API (поиск городов, ПВЗ и т.д.) ─
    const token    = await getCdekToken()
    const endpoint = url.searchParams.get('endpoint') || '/v2/location/cities'
    const apiUrl   = new URL(`${CDEK_API}${endpoint}`)

    url.searchParams.forEach((val, key) => {
      if (key !== 'action' && key !== 'endpoint') apiUrl.searchParams.set(key, val)
    })

    const cdekResp = await fetch(apiUrl.toString(), {
      headers: { 'Authorization': `Bearer ${token}` },
    })
    const data = await cdekResp.json()
    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status:  500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
