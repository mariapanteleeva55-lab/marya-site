const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const params = new URLSearchParams({
    grant_type:    'client_credentials',
    client_id:     'uejYeTXuvgJfQhzbb5cGnU5PZMt1EIah',
    client_secret: '8SzS9ttOFDH3oSHasXu6b58bxakZkftf',
  })

  const response = await fetch('https://api.cdek.ru/v2/oauth/token', {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    params,
  })

  const data = await response.json()

  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
