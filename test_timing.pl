#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Time::HiRes qw(time);

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @lines = do { local (@ARGV) = 'perl-tests/base/lex.t'; <> };

for my $n (21, 22, 26) {
    my $code = join('', @lines[0..$n-1]);
    my $start = time();
    my $result = $parser->parse_string($code);
    my $elapsed = time() - $start;
    
    printf "Lines 1-%d: %s (%.3f seconds)\n", $n, ($result ? "PASS" : "FAIL"), $elapsed;
}
