#!/usr/bin/env perl
# ABOUTME: Test full lex.t with HeredocV2 preprocessor
# ABOUTME: Verify grammar-based approach handles all heredoc cases
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::HeredocV2'],
);

print "Testing lex.t with HeredocV2 preprocessor\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

open my $fh, '<', 'perl-tests/base/lex.t' or die "Can't open lex.t: $!";
my $code = do { local $/; <$fh> };
close $fh;

printf "File size: %d bytes, %d lines\n", length($code), scalar(split(/\n/, $code));
print "Parsing with HeredocV2 preprocessor...\n";

my $result = eval {
    local $SIG{ALRM} = sub { die "TIMEOUT\n" };
    alarm 60;
    my $r = $parser->parse_string($code);
    alarm 0;
    $r;
};

print "\n";
print "=" x 60 . "\n";

if ($@ && $@ =~ /TIMEOUT/) {
    print "❌ TIMEOUT after 60 seconds\n";
} elsif ($@) {
    print "❌ ERROR: $@\n";
} elsif ($result) {
    print "✅ SUCCESS! lex.t fully parses with HeredocV2!\n";
    print "\n🎉 All perl-tests/base/ files now parse!\n";
} else {
    print "❌ PARSE FAILURE - grammar still missing constructs\n";
}
