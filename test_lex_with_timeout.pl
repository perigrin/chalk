#!/usr/bin/env perl
# ABOUTME: Test lex.t with extended timeout to distinguish timeout vs parse failure
# ABOUTME: Use alarm to enforce timeout and report actual status
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing lex.t with 60-second timeout\n";
print "=" x 60 . "\n\n";

open my $fh, '<', 'perl-tests/base/lex.t' or die "Can't open lex.t: $!";
my $code = do { local $/; <$fh> };
close $fh;

printf "File size: %d bytes, %d lines\n", length($code), scalar(split(/\n/, $code));
print "Starting parse...\n";

local $SIG{__WARN__} = sub {};
my $result;
my $timed_out = 0;

eval {
    local $SIG{ALRM} = sub { die "TIMEOUT\n" };
    alarm 60;
    $result = $parser->parse_string($code);
    alarm 0;
};

if ($@ && $@ =~ /TIMEOUT/) {
    print "\n⏱️  TIMEOUT after 60 seconds\n";
    print "The parser is taking too long (exponential backtracking?)\n";
    $timed_out = 1;
} elsif ($@) {
    print "\n❌ ERROR: $@\n";
} elsif ($result) {
    print "\n✅ SUCCESS! lex.t parses completely!\n";
} else {
    print "\n❌ PARSE FAILURE (not a timeout, actual grammar mismatch)\n";
}

print "\n";
print "=" x 60 . "\n";
if ($timed_out) {
    print "Result: TIMEOUT - need to investigate performance\n";
} elsif ($result) {
    print "Result: PASS - lex.t now fully parses!\n";
} else {
    print "Result: FAIL - grammar still missing constructs\n";
}
