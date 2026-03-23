import { Exa } from 'exa-js';

// Singleton instance of the Exa client
// Tools should import this instance rather than creating their own
export const exa = new Exa(process.env.EXA_API_KEY || '');
