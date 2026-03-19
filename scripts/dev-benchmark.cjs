#!/usr/bin/env node
/**
 * Model Benchmark — OpenCode CLI
 * Сравнивает модели по скорости и токенам напрямую через API
 * 
 * Использование:
 *   node scripts/dev-benchmark.cjs [--models m1,m2] [--task "описание"] [--runs n]
 *   node scripts/dev-benchmark.cjs --help
 * 
 * Доступные модели:
 *   MiniMax-M2.5, MiniMax-M2.1         (MiniMax Portal, free)
 *   stepfun-3.5, hunter-alpha, healer-alpha, gemini-3-flash  (OpenRouter, free)
 *   nemotron-3, deepseek-v3.2, kimi-k2.5, grok-4.1-fast   (OpenRouter Nvidia)
 *   llama-3.3-70b, gpt-oss-120b, kimi-k2-groq          (Groq)
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

const HOME = process.env.HOME || '/Users/ihyart';

function loadEnv() {
  const envPath = path.join(HOME, '.openclaw', '.env');
  if (!fs.existsSync(envPath)) {
    console.error('❌ ~/.openclaw/.env not found');
    process.exit(1);
  }
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
  // ============ MiniMax Portal (free) ============
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
      body: {
        model: 'MiniMax-M2.5',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
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
      body: {
        model: 'MiniMax-M2.1',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
    }
  },
  
  // ============ Groq (почти free) ============
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
      body: {
        model: 'llama-3.3-70b-versatile',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
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
      body: {
        model: 'openai/gpt-oss-120b',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
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
      body: {
        model: 'moonshotai/kimi-k2-instruct-0905',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
    }
  },
  
  // ============ OpenRouter (free models) ============
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
      body: {
        model: 'stepfun/step-3.5-flash:free',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
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
      body: {
        model: 'openrouter/hunter-alpha',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
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
      body: {
        model: 'openrouter/healer-alpha',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
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
      body: {
        model: 'google/gemini-3.1-flash-lite-preview',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
    }
  },
  
  // ============ OpenRouter Nvidia (free) ============
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
      body: {
        model: 'nvidia/nemotron-3-super-120b-a12b:free',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
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
      body: {
        model: 'deepseek/deepseek-v3.2',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
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
      body: {
        model: 'moonshotai/kimi-k2.5',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
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
      body: {
        model: 'x-ai/grok-4.1-fast',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 512
      }
    }),
    parse: (data) => {
      const json = JSON.parse(data);
      return {
        content: json.choices?.[0]?.message?.content || '',
        inputTokens: json.usage?.prompt_tokens || 0,
        outputTokens: json.usage?.completion_tokens || 0
      };
    }
  }
};

const DEFAULT_TASK = `Создай простой калькулятор на HTML/CSS/JS одной страницей. 
Только код, без объяснений. Калькулятор должен иметь:
- 4 кнопки операций (+ - * /)
- кнопку =
- кнопку C для очистки
- дисплей
- красивый современный дизайн`;

function parseArgs() {
  const args = process.argv.slice(2);
  const config = {
    models: Object.keys(MODELS),
    task: DEFAULT_TASK,
    runs: 1
  };
  
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--models' && args[i + 1]) {
      config.models = args[++i].split(',');
    } else if (args[i] === '--task' && args[i + 1]) {
      config.task = args[++i];
    } else if (args[i] === '--runs' && args[i + 1]) {
      config.runs = parseInt(args[++i]);
    } else if (args[i] === '--help') {
      console.log(`
╔══════════════════════════════════════════════════════════════════╗
║               DEV BENCHMARK — Справка                           ║
╚══════════════════════════════════════════════════════════════════╝

Usage: node dev-benchmark.cjs [options]

Options:
  --models m1,m2,...  Список моделей через запятую (по умолчанию: все)
  --task "prompt"    Задача для тестирования
  --runs n           Количество прогонов (по умолчанию: 1)
  --help             Показать эту справку

Доступные модели:
${Object.keys(MODELS).map(m => `  • ${m}`).join('\n')}

Примеры:
  node dev-benchmark.cjs --models MiniMax-M2.5,llama-3.3-70b --runs 3
  node dev-benchmark.cjs --models stepfun-3.5,grok-4.1-fast --task "напиши функцию на python"
      `.trim());
      process.exit(0);
    }
  }
  
  config.models = config.models.filter(m => MODELS[m]);
  if (config.models.length === 0) {
    console.error('❌ Нет доступных моделей');
    console.log('Доступны:', Object.keys(MODELS).join(', '));
    process.exit(1);
  }
  
  return config;
}

function makeRequest(modelId, prompt) {
  return new Promise((resolve, reject) => {
    const m = MODELS[modelId];
    if (!m || !m.apiKey) {
      reject(new Error(`Модель ${modelId} недоступна (нет API ключа)`));
      return;
    }
    
    const req = m.buildRequest(prompt);
    
    const options = {
      hostname: m.baseUrl,
      port: 443,
      path: req.path,
      method: 'POST',
      headers: m.headers(m.apiKey)
    };
    
    const startTime = Date.now();
    let firstTokenTime = null;
    let responseData = '';
    
    const reqObj = https.request(options, (res) => {
      res.on('data', (chunk) => {
        if (firstTokenTime === null) {
          firstTokenTime = Date.now() - startTime;
        }
        responseData += chunk;
      });
      
      res.on('end', () => {
        const totalTime = Date.now() - startTime;
        
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode}: ${responseData.slice(0, 200)}`));
          return;
        }
        
        try {
          const parsed = m.parse(responseData);
          resolve({
            model: modelId,
            provider: m.provider,
            ttft: firstTokenTime,
            totalTime,
            inputTokens: parsed.inputTokens,
            outputTokens: parsed.outputTokens,
            totalTokens: parsed.inputTokens + parsed.outputTokens,
            contentLength: parsed.content.length,
            contentPreview: parsed.content.slice(0, 100).replace(/\n/g, ' ')
          });
        } catch (e) {
          reject(new Error(`Ошибка парсинга: ${e.message}`));
        }
      });
    });
    
    reqObj.on('error', reject);
    reqObj.write(JSON.stringify(req.body));
    reqObj.end();
  });
}

async function runBenchmark(config) {
  console.log('\n' + '═'.repeat(80));
  console.log('🚀 DEV BENCHMARK — Сравнение моделей для разработки');
  console.log('═'.repeat(80));
  console.log(`Task: "${config.task.slice(0, 60)}..."`);
  console.log(`Models: ${config.models.length} выбрано`);
  console.log(`Runs: ${config.runs}\n`);
  
  const results = [];
  
  for (const modelId of config.models) {
    console.log(`\n⏳ ${modelId}...`);
    
    const runs = [];
    for (let i = 0; i < config.runs; i++) {
      try {
        const result = await makeRequest(modelId, config.task);
        runs.push(result);
        console.log(`   Run ${i + 1}: TTFT=${result.ttft}ms, Total=${result.totalTime}ms, Tokens=${result.totalTokens}`);
      } catch (e) {
        console.log(`   ❌ Ошибка: ${e.message}`);
      }
    }
    
    if (runs.length > 0) {
      const avg = {
        model: runs[0].model,
        provider: runs[0].provider,
        ttft: Math.round(runs.reduce((a, r) => a + r.ttft, 0) / runs.length),
        totalTime: Math.round(runs.reduce((a, r) => a + r.totalTime, 0) / runs.length),
        inputTokens: Math.round(runs.reduce((a, r) => a + r.inputTokens, 0) / runs.length),
        outputTokens: Math.round(runs.reduce((a, r) => a + r.outputTokens, 0) / runs.length),
        totalTokens: Math.round(runs.reduce((a, r) => a + r.totalTokens, 0) / runs.length),
        contentLength: Math.round(runs.reduce((a, r) => a + r.contentLength, 0) / runs.length),
        contentPreview: runs[0].contentPreview,
        runs: runs.length
      };
      results.push(avg);
    }
  }
  
  return results;
}

function printResults(results) {
  console.log('\n' + '═'.repeat(80));
  console.log('📊 РЕЗУЛЬТАТЫ');
  console.log('═'.repeat(80));
  
  if (results.length === 0) {
    console.log('Нет результатов.');
    return;
  }
  
  results.sort((a, b) => a.totalTime - b.totalTime);
  
  console.log('\n| #  | Model                 | Provider      | TTFT   | Total  | In  | Out |');
  console.log('|----|-----------------------|---------------|--------|--------|-----|-----|');
  
  results.forEach((r, idx) => {
    const rank = (idx + 1).toString().padStart(2);
    console.log(`| ${rank} | ${r.model.padEnd(21)} | ${r.provider.padEnd(13)} | ${String(r.ttft).padStart(5)}ms | ${String(r.totalTime).padStart(5)}ms | ${String(r.inputTokens).padStart(3)} | ${String(r.outputTokens).padStart(3)} |`);
  });
  
  console.log('\n' + '─'.repeat(80));
  console.log('🏆 ПОБЕДИТЕЛИ:');
  console.log('   ⚡ TTFT (скорость до 1-го токена):', results[0].model, `(${results[0].ttft}ms)`);
  console.log('   🚀 Total (общее время):', results[0].model, `(${results[0].totalTime}ms)`);
  const maxOutput = [...results].sort((a, b) => b.outputTokens - a.outputTokens)[0];
  console.log('   📝 Max Output:', maxOutput.model, `(${maxOutput.outputTokens} tokens)`);
  
  console.log('\n' + '─'.repeat(80));
  console.log('📄 ПРЕВЬЮ ОТВЕТА (победитель):');
  console.log(results[0].contentPreview + '...');
}

async function main() {
  const config = parseArgs();
  
  try {
    const results = await runBenchmark(config);
    printResults(results);
  } catch (e) {
    console.error('❌ Бенчмарк провалился:', e.message);
    process.exit(1);
  }
}

main();
