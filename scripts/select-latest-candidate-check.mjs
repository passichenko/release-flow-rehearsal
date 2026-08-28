#!/usr/bin/env node

import { pathToFileURL } from 'node:url';

const GITHUB_ACTIONS_APP_ID = 15368;

export function selectLatestCandidateCheck(pages, expectedName) {
  if (!Array.isArray(pages)) throw new Error('check response must be an array of pages');
  if (typeof expectedName !== 'string' || expectedName.length === 0) {
    throw new Error('expected check name is required');
  }

  const matching = [];
  for (const page of pages) {
    if (!page || !Array.isArray(page.check_runs)) {
      throw new Error('check response page is missing check_runs');
    }
    for (const check of page.check_runs) {
      if (check?.name !== expectedName || check?.app?.id !== GITHUB_ACTIONS_APP_ID) continue;
      if (!Number.isSafeInteger(check.id) || check.id < 1) {
        throw new Error('matching check has an invalid id');
      }
      matching.push(check);
    }
  }

  return matching.reduce((latest, check) => (!latest || check.id > latest.id ? check : latest), null);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const expectedName = process.argv[2];
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  const latest = selectLatestCandidateCheck(JSON.parse(input), expectedName);
  process.stdout.write(`${JSON.stringify(latest)}\n`);
}
