import { describe, it, expect } from 'vitest';
import { applyCompatCoercions } from '../coercion.js';

describe('applyCompatCoercions', () => {
  it('keeps strict behavior when compat mode is absent', () => {
    const input = { entity: 'company', criteria: ['has funding'] };
    const result = applyCompatCoercions('searches.create', input);

    expect(result.enabled).toBe(false);
    expect(result.preview).toBe(false);
    expect(result.effectiveMode).toBe('strict');
    expect(result.args).toEqual(input);
    expect(result.coercions).toHaveLength(0);
  });

  it('coerces entity string, criteria array, and numeric string in safe mode', () => {
    const result = applyCompatCoercions('searches.create', {
      compat: { mode: 'safe' },
      entity: 'company',
      criteria: ['has funding'],
      count: '25',
    });

    expect(result.enabled).toBe(true);
    expect(result.preview).toBe(false);
    expect(result.effectiveMode).toBe('safe');
    expect(result.args.entity).toEqual({ type: 'company' });
    expect(result.args.criteria).toEqual([{ description: 'has funding' }]);
    expect(result.args.count).toBe(25);
    expect(result.coercions.map(c => c.path)).toEqual([
      'args.entity',
      'args.criteria',
      'args.count',
    ]);
  });

  it('uses server default safe mode when compat is absent', () => {
    const result = applyCompatCoercions(
      'searches.create',
      {
        entity: 'company',
        criteria: ['has funding'],
      },
      'safe',
    );

    expect(result.enabled).toBe(true);
    expect(result.effectiveMode).toBe('safe');
    expect(result.args.entity).toEqual({ type: 'company' });
    expect(result.args.criteria).toEqual([{ description: 'has funding' }]);
  });

  it('supports per-call strict override when default mode is safe', () => {
    const result = applyCompatCoercions(
      'searches.create',
      {
        compat: { mode: 'strict' },
        entity: 'company',
      },
      'safe',
    );

    expect(result.enabled).toBe(false);
    expect(result.effectiveMode).toBe('strict');
    expect(result.args.entity).toBe('company');
    expect(result.coercions).toHaveLength(0);
  });

  it('supports preview flag', () => {
    const result = applyCompatCoercions('searches.create', {
      compat: { mode: 'safe', preview: true },
      entity: 'company',
    });

    expect(result.preview).toBe(true);
    expect(result.enabled).toBe(true);
    expect(result.args.entity).toEqual({ type: 'company' });
  });

  it('coerces nested tasks.create args safely', () => {
    const result = applyCompatCoercions('tasks.create', {
      compat: { mode: 'safe' },
      type: 'convergent.search',
      args: {
        entity: 'company',
        criteria: ['profitable'],
        count: '10',
      },
    });

    expect(result.args.args).toEqual({
      entity: { type: 'company' },
      criteria: [{ description: 'profitable' }],
      count: 10,
    });
    expect(result.coercions.map(c => c.path)).toEqual([
      'args.args.entity',
      'args.args.criteria',
      'args.args.count',
    ]);
  });

  it('coerces options arrays of strings in enrichments', () => {
    const result = applyCompatCoercions('websets.create', {
      compat: { mode: 'safe' },
      enrichments: [
        { description: 'Stage', format: 'options', options: ['Seed', 'Series A'] },
      ],
    });

    expect(result.args.enrichments).toEqual([
      {
        description: 'Stage',
        format: 'options',
        options: [{ label: 'Seed' }, { label: 'Series A' }],
      },
    ]);
    expect(result.coercions.map(c => c.path)).toContain('args.enrichments[0].options');
  });

  it('does not coerce malformed cron expressions', () => {
    const result = applyCompatCoercions('monitors.create', {
      compat: { mode: 'safe' },
      cron: 'not-a-cron',
    });

    expect(result.args.cron).toBe('not-a-cron');
    expect(result.coercions).toHaveLength(0);
  });

  it('ignores unsupported compat mode and reports warning', () => {
    const result = applyCompatCoercions('searches.create', {
      compat: { mode: 'aggressive' },
      entity: 'company',
    }, 'safe');

    expect(result.enabled).toBe(false);
    expect(result.args.entity).toBe('company');
    expect(result.warnings).toEqual([
      'Unsupported compat mode "aggressive"; ignored.',
    ]);
  });

  it('warns on invalid preview value', () => {
    const result = applyCompatCoercions('searches.create', {
      compat: { mode: 'safe', preview: 'yes' },
    });

    expect(result.preview).toBe(false);
    expect(result.warnings).toEqual([
      'Invalid compat preview value "yes"; expected boolean.',
    ]);
  });
});
