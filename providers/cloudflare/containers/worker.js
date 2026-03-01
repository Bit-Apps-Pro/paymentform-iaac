export class PaymentformClient {
  constructor(env) {
    this.env = env;
    this.defaultPort = 8080;
  }

  async fetch(request) {
    const url = new URL(request.url);
    
    const containerUrl = `http://localhost:${this.defaultPort}${url.pathname}`;
    
    try {
      const response = await fetch(containerUrl, {
        method: request.method,
        headers: request.headers,
        body: request.body
      });
      
      return new Response(response.body, {
        status: response.status,
        headers: response.headers
      });
    } catch (error) {
      return new Response(`Container error: ${error.message}`, {
        status: 502,
        headers: { "Content-Type": "text/plain" }
      });
    }
  }
}

export class PaymentformRenderer {
  constructor(env) {
    this.env = env;
    this.defaultPort = 8080;
  }

  async fetch(request) {
    const url = new URL(request.url);
    
    const containerUrl = `http://localhost:${this.defaultPort}${url.pathname}`;
    
    try {
      const response = await fetch(containerUrl, {
        method: request.method,
        headers: request.headers,
        body: request.body
      });
      
      return new Response(response.body, {
        status: response.status,
        headers: response.headers
      });
    } catch (error) {
      return new Response(`Container error: ${error.message}`, {
        status: 502,
        headers: { "Content-Type": "text/plain" }
      });
    }
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    
    if (url.pathname.startsWith("/renderer")) {
      const doId = env.PAYMENTFORM_RENDERER.idFromName("renderer");
      const stub = env.PAYMENTFORM_RENDERER.get(doId);
      return stub.fetch(request);
    }
    
    const doId = env.PAYMENTFORM_CLIENT.idFromName("client");
    const stub = env.PAYMENTFORM_CLIENT.get(doId);
    return stub.fetch(request);
  }
};
