#!/usr/bin/env node

import { pathToFileURL } from 'node:url';

const fullSha = /^[0-9a-f]{40}$/;

export function verifyCandidateRefState({
  candidateSha,
  candidateTip,
  productionBase,
  productionTip,
  pullRequest,
}) {
  for (const [name, value] of Object.entries({ candidateSha, productionBase, productionTip })) {
    if (!fullSha.test(value)) throw new Error(`${name} must be a full lowercase SHA`);
  }
  if (candidateTip && !fullSha.test(candidateTip)) {
    throw new Error('candidateTip must be absent or a full lowercase SHA');
  }

  if (productionTip === productionBase) {
    if (candidateTip !== candidateSha) {
      throw new Error(
        `Candidate branch disappeared before Production Sync: expected ${candidateSha}, found ${candidateTip || 'an absent branch'}`,
      );
    }
    return 'before-production-sync';
  }

  if (productionTip !== candidateSha) {
    throw new Error(
      `production must equal ${productionBase} or exact candidate ${candidateSha}, found ${productionTip}`,
    );
  }
  if (
    pullRequest?.state !== 'closed' ||
    pullRequest?.merged !== true ||
    pullRequest?.merge_commit_sha !== candidateSha
  ) {
    throw new Error(
      'candidate branch may be absent only after exact Production Sync and exact-SHA PR merge recording',
    );
  }
  if (candidateTip && candidateTip !== candidateSha) {
    throw new Error(
      `unexpected recovery candidate branch: expected absent or ${candidateSha}, found ${candidateTip}`,
    );
  }
  return 'after-production-sync';
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [productionTip, productionBase, candidateSha, candidateTip = ''] = process.argv.slice(2);
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  const state = verifyCandidateRefState({
    candidateSha,
    candidateTip,
    productionBase,
    productionTip,
    pullRequest: JSON.parse(input),
  });
  process.stdout.write(`${state}\n`);
}
