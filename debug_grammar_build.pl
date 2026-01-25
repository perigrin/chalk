#!/usr/bin/env perl
use 5.42.0;
use lib 'lib';

$SIG{ALRM} = sub {
    warn "TIMEOUT! Stack trace:\n";
    require Carp;
    Carp::cluck("Hung here");
    exit 1;
};

alarm 15;

say "=== Reading BNF file ===";
open my $fh, '<', 'grammar/chalk.bnf' or die $!;
my $content = do { local $/; <$fh> };
close $fh;
say "OK: Read " . length($content) . " bytes";

say "=== Loading Chalk::Grammar ===";
require Chalk::Grammar;
say "OK: Loaded";

say "=== Building grammar from BNF ===";
my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');
say "OK: Grammar built";

say "=== Checking grammar ===";
say "Start symbol: " . $grammar->start_symbol if $grammar;
say "OK: All done";

alarm 0;
