#!/usr/bin/env perl
use 5.42.0;
use lib 'lib';

# Trace where the hang occurs
$SIG{ALRM} = sub {
    warn "TIMEOUT! Stack trace:\n";
    require Carp;
    Carp::cluck("Hung here");
    exit 1;
};

alarm 10;  # 10 second timeout with stack trace

say "=== Step 1: Loading Chalk::Grammar::Chalk ===";
require Chalk::Grammar::Chalk;
say "OK: Chalk::Grammar::Chalk loaded";

say "=== Step 2: Creating Chalk grammar object ===";
my $chalk = Chalk::Grammar::Chalk->new();
say "OK: Chalk object created";

say "=== Step 3: Getting grammar ===";
my $grammar = $chalk->grammar();
say "OK: Grammar obtained";

say "=== Step 4: Checking start symbol ===";
my $start = $grammar->start_symbol;
say "OK: Start symbol: $start";

say "=== SUCCESS: All steps completed ===";
alarm 0;
