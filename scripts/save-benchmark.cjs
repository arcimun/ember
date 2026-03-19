#!/usr/bin/env node
/**
 * Save benchmark results to files for analysis
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

const HOME = process.env.HOME || '/Users/ihyart';

function loadEnv() {
  const envPath = path.join(HOME, '.openclaw', '.env');
  const content = fs.readFileSync(envPath, 'utf8');
  const env = {};
  content.split('\n').forEach(line => {
    const t = line.trim();
    if (t && !t.startsWith('#') && t.includes('=')) {
      const [k, ...v] = t.split('=');
      env[k] = v.join('=').trim();
    }
  });
  return env;
}

const env = loadEnv();

const MODELS = {
  'MiniMax-M2.5': {
    provider: 'minimax-portal',
    apiKey: env.MINIMAX_API_KEY,
    baseUrl: 'api.minimaxi.chat',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json'
    }),
    buildRequest: (prompt) => ({
      path: '/v1/text/chatcompletion_v2',
      body: { model: 'MiniMax-M2.5', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'MiniMax-M2.1': {
    provider: 'minimax-portal',
    apiKey: env.MINIMAX_API_KEY,
    baseUrl: 'api.minimaxi.chat',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json'
    }),
    buildRequest: (prompt) => ({
      path: '/v1/text/chatcompletion_v2',
      body: { model: 'MiniMax-M2.1', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'llama-3.3-70b': {
    provider: 'groq',
    apiKey: env.GROQ_API_KEY,
    baseUrl: 'api.groq.com',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json'
    }),
    buildRequest: (prompt) => ({
      path: '/openai/v1/chat/completions',
      body: { model: 'llama-3.3-70b-versatile', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'gpt-oss-120b': {
    provider: 'groq',
    apiKey: env.GROQ_API_KEY,
    baseUrl: 'api.groq.com',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json'
    }),
    buildRequest: (prompt) => ({
      path: '/openai/v1/chat/completions',
      body: { model: 'openai/gpt-oss-120b', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'kimi-k2-groq': {
    provider: 'groq',
    apiKey: env.GROQ_API_KEY,
    baseUrl: 'api.groq.com',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json'
    }),
    buildRequest: (prompt) => ({
      path: '/openai/v1/chat/completions',
      body: { model: 'moonshotai/kimi-k2-instruct-0905', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'stepfun-3.5': {
    provider: 'openrouter',
    apiKey: env.OPENROUTER_API_KEY,
    baseUrl: 'openrouter.ai',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://opencode.ai',
      'X-Title': 'DevBenchmark'
    }),
    buildRequest: (prompt) => ({
      path: '/api/v1/chat/completions',
      body: { model: 'stepfun/step-3.5-flash:free', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'hunter-alpha': {
    provider: 'openrouter',
    apiKey: env.OPENROUTER_API_KEY,
    baseUrl: 'openrouter.ai',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://opencode.ai',
      'X-Title': 'DevBenchmark'
    }),
    buildRequest: (prompt) => ({
      path: '/api/v1/chat/completions',
      body: { model: 'openrouter/hunter-alpha', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'healer-alpha': {
    provider: 'openrouter',
    apiKey: env.OPENROUTER_API_KEY,
    baseUrl: 'openrouter.ai',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://opencode.ai',
      'X-Title': 'DevBenchmark'
    }),
    buildRequest: (prompt) => ({
      path: '/api/v1/chat/completions',
      body: { model: 'openrouter/healer-alpha', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'gemini-3-flash': {
    provider: 'openrouter',
    apiKey: env.OPENROUTER_API_KEY,
    baseUrl: 'openrouter.ai',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://opencode.ai',
      'X-Title': 'DevBenchmark'
    }),
    buildRequest: (prompt) => ({
      path: '/api/v1/chat/completions',
      body: { model: 'google/gemini-3.1-flash-lite-preview', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'nemotron-3': {
    provider: 'openrouter',
    apiKey: env.OPENROUTER_API_KEY,
    baseUrl: 'openrouter.ai',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://opencode.ai',
      'X-Title': 'DevBenchmark'
    }),
    buildRequest: (prompt) => ({
      path: '/api/v1/chat/completions',
      body: { model: 'nvidia/nemotron-3-super-120b-a12b:free', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'deepseek-v3.2': {
    provider: 'openrouter',
    apiKey: env.OPENROUTER_API_KEY,
    baseUrl: 'openrouter.ai',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://opencode.ai',
      'X-Title': 'DevBenchmark'
    }),
    buildRequest: (prompt) => ({
      path: '/api/v1/chat/completions',
      body: { model: 'deepseek/deepseek-v3.2', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'kimi-k2.5': {
    provider: 'openrouter',
    apiKey: env.OPENROUTER_API_KEY,
    baseUrl: 'openrouter.ai',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://opencode.ai',
      'X-Title': 'DevBenchmark'
    }),
    buildRequest: (prompt) => ({
      path: '/api/v1/chat/completions',
      body: { model: 'moonshotai/kimi-k2.5', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  },
  'grok-4.1-fast': {
    provider: 'openrouter',
    apiKey: env.OPENROUTER_API_KEY,
    baseUrl: 'openrouter.ai',
    headers: (key) => ({
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://opencode.ai',
      'X-Title': 'DevBenchmark'
    }),
    buildRequest: (prompt) => ({
      path: '/api/v1/chat/completions',
      body: { model: 'x-ai/grok-4.1-fast', messages: [{ role: 'user', content: prompt }], max_tokens: 2048 }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return json.choices?.[0]?.message?.content || '';
    }
  }
};

const TASK = `Создай простой калькулятор на HTML/CSS/JS одной страницей. 
Только код, без объяснений. Калькулятор должен иметь:
- 4 кнопки операций (+ - * /)
- кнопку =
- кнопку C для очистки
- дисплей
- красивый современный дизайн`;

function makeRequest(modelId) {
  return new Promise((resolve, reject) => {
    const m = MODELS[modelId];
    const req = m.buildRequest(TASK);
    const options = {
      hostname: m.baseUrl,
      port: 443,
      path: req.path,
      method: 'POST',
      headers: m.headers(m.apiKey)
    };
    
    const reqObj = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const content = m.parse(data);
          resolve(content);
        } catch (e) {
          reject(e);
        }
      });
    });
    
    reqObj.on('error', reject);
    reqObj.write(JSON.stringify(req.body));
    reqObj.end();
  });
}

function extractHTML(content) {
  let html = content;
  
  // Extract from ```html ... ``` or ``` ... ```
  const codeBlockMatch = content.match(/```(?:html)?\s*([\s\S]*?)```/);
  if (codeBlockMatch) {
    html = codeBlockMatch[1];
  }
  
  // If no code block, use the whole thing
  if (!html.includes('<!DOCTYPE') && !html.includes('<html')) {
    html = content;
  }
  
  return html.trim();
}

async function main() {
  const outputDir = path.join(__dirname, '..', 'benchmark-results');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }
  
  console.log('Saving code from all models...\n');
  
  for (const modelId of Object.keys(MODELS)) {
    try {
      console.log(`Fetching ${modelId}...`);
      const content = await makeRequest(modelId);
      const html = extractHTML(content);
      
      const filename = `${modelId}.html`;
      fs.writeFileSync(path.join(outputDir, filename), html);
      console.log(`  ✓ Saved to ${filename} (${html.length} chars)`);
    } catch (e) {
      console.log(`  ❌ Error: ${e.message}`);
    }
  }
  
  console.log('\nDone!');
}

main();
