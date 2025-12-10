#!/usr/bin/env perl
# ABOUTME: Baseline test harness for parsing perl-tests/base/*.t files
# ABOUTME: Documents which perl5 base test files currently parse successfully
use 5.42.0;
use Test2::V0;

# This test is blocked until Chalk performance is ready for development of full Perl 5 test suite.
# The perl.bnf grammar used here is a legacy full Perl grammar that is
# too complex for our current parser. Once chalk.bnf performance is sufficient,
# we'll re-write perl.bnf to start as a copy of chalk.bnf and expand from there.
# Chalk will always be a subset of Perl 5.
plan skip_all => 'Blocked: Waiting for Chalk performance to be ready for development of full Perl 5 test suite';
