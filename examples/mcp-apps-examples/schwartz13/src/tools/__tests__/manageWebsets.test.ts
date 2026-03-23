import { describe, it, expect, vi } from 'vitest';
import { registerManageWebsetsTool } from '../manageWebsets.js';

function setupTool(exa: any, options?: { defaultCompatMode?: 'safe' | 'strict' }) {
  let handler: ((input: any) => Promise<any>) | null = null;
  let inputSchema: { parse: (input: unknown) => unknown } | null = null;

  const fakeServer = {
    registerTool: vi.fn((_name, config, fn) => {
      handler = fn;
      inputSchema = config.inputSchema;
    }),
  };

  registerManageWebsetsTool(fakeServer as any, exa, options);
  expect(handler).not.toBeNull();
  expect(inputSchema).not.toBeNull();

  const call = async (input: Record<string, unknown>) => {
    const parsed = inputSchema!.parse(input);
    return handler!(parsed);
  };

  return { call };
}

describe('registerManageWebsetsTool', () => {
  it('applies safe compat coercions and returns metadata', async () => {
    const createSpy = vi.fn().mockResolvedValue({
      id: 'search_1',
      status: 'completed',
      query: 'ai startups',
    });

    const exa = {
      websets: {
        searches: {
          create: createSpy,
        },
      },
    } as any;

    const { call } = setupTool(exa);

    const result = await call({
      operation: 'searches.create',
      args: {
        compat: { mode: 'safe' },
        websetId: 'ws_1',
        query: 'ai startups',
        entity: 'company',
        criteria: ['has funding'],
        count: '25',
      },
    });

    expect(createSpy).toHaveBeenCalledTimes(1);
    expect(createSpy).toHaveBeenCalledWith('ws_1', {
      query: 'ai startups',
      count: 25,
      entity: { type: 'company' },
      criteria: [{ description: 'has funding' }],
    });

    const body = JSON.parse(result.content[0].text);
    expect(body._coercions).toHaveLength(3);
    expect(body._coercions.map((c: { path: string }) => c.path)).toEqual([
      'args.entity',
      'args.criteria',
      'args.count',
    ]);
  });

  it('accepts legacy args envelope without coercion when values are already valid', async () => {
    const createSpy = vi.fn().mockResolvedValue({
      id: 'search_1',
      status: 'completed',
      query: 'ai startups',
    });

    const exa = {
      websets: {
        searches: {
          create: createSpy,
        },
      },
    } as any;

    const { call } = setupTool(exa);

    await call({
      operation: 'searches.create',
      args: {
        websetId: 'ws_1',
        query: 'ai startups',
        entity: { type: 'company' },
        criteria: [{ description: 'has funding' }],
      },
    });

    expect(createSpy).toHaveBeenCalledWith('ws_1', {
      query: 'ai startups',
      entity: { type: 'company' },
      criteria: [{ description: 'has funding' }],
    });
  });

  it('fails validation in strict mode for uncoerced compatibility formats', async () => {
    const createSpy = vi.fn();

    const exa = {
      websets: {
        searches: {
          create: createSpy,
        },
      },
    } as any;

    const { call } = setupTool(exa);
    const result = await call({
      operation: 'searches.create',
      websetId: 'ws_1',
      query: 'ai startups',
      entity: 'company',
    });

    expect(createSpy).not.toHaveBeenCalled();
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('Error in searches.create: Validation failed');
  });

  it('reports warning for unsupported compat mode', async () => {
    const createSpy = vi.fn().mockResolvedValue({
      id: 'search_1',
      status: 'completed',
      query: 'ai startups',
    });

    const exa = {
      websets: {
        searches: {
          create: createSpy,
        },
      },
    } as any;

    const { call } = setupTool(exa);

    const result = await call({
      operation: 'searches.create',
      compat: { mode: 'aggressive' as any },
      websetId: 'ws_1',
      query: 'ai startups',
    });

    const body = JSON.parse(result.content[0].text);
    expect(body._warnings).toEqual(['Unsupported compat mode "aggressive"; ignored.']);
  });

  it('honors server-level default compat mode and per-call strict override', async () => {
    const createSpy = vi.fn().mockResolvedValue({
      id: 'search_1',
      status: 'completed',
      query: 'ai startups',
    });

    const exa = {
      websets: {
        searches: {
          create: createSpy,
        },
      },
    } as any;

    const { call } = setupTool(exa, { defaultCompatMode: 'safe' });

    await call({
      operation: 'searches.create',
      websetId: 'ws_1',
      query: 'ai startups',
      entity: 'company',
    });

    expect(createSpy).toHaveBeenNthCalledWith(1, 'ws_1', {
      query: 'ai startups',
      entity: { type: 'company' },
    });

    const strictResult = await call({
      operation: 'searches.create',
      compat: { mode: 'strict' },
      websetId: 'ws_1',
      query: 'ai startups',
      entity: 'company',
    });

    expect(createSpy).toHaveBeenCalledTimes(1);
    expect(strictResult.isError).toBe(true);
    expect(strictResult.content[0].text).toContain('Error in searches.create: Validation failed');
  });

  it('returns preview without executing handler when compat.preview=true', async () => {
    const createSpy = vi.fn().mockResolvedValue({
      id: 'search_1',
      status: 'completed',
      query: 'ai startups',
    });

    const exa = {
      websets: {
        searches: {
          create: createSpy,
        },
      },
    } as any;

    const { call } = setupTool(exa);

    const result = await call({
      operation: 'searches.create',
      compat: { mode: 'safe', preview: true },
      websetId: 'ws_1',
      query: 'ai startups',
      entity: 'company',
    });

    expect(createSpy).not.toHaveBeenCalled();
    const body = JSON.parse(result.content[0].text);
    expect(body.preview).toBe(true);
    expect(body.execution).toBe('skipped');
    expect(body.effectiveCompatMode).toBe('safe');
    expect(body.normalizedArgs).toEqual({
      websetId: 'ws_1',
      query: 'ai startups',
      entity: { type: 'company' },
    });
    expect(body._coercions).toHaveLength(1);
  });

  it('preserves enrichment options when creating websets', async () => {
    const createSpy = vi.fn().mockResolvedValue({
      id: 'ws_1',
      status: 'ready',
      search: { query: 'ai startups' },
    });

    const exa = {
      websets: {
        create: createSpy,
      },
    } as any;

    const { call } = setupTool(exa);

    await call({
      operation: 'websets.create',
      searchQuery: 'ai startups',
      enrichments: [
        {
          description: 'Company stage',
          format: 'options',
          options: [{ label: 'Seed' }, { label: 'Series A' }],
        },
      ],
    });

    expect(createSpy).toHaveBeenCalledWith({
      search: {
        query: 'ai startups',
        count: 10,
      },
      enrichments: [
        {
          description: 'Company stage',
          format: 'options',
          options: [{ label: 'Seed' }, { label: 'Series A' }],
        },
      ],
    });
  });
});
