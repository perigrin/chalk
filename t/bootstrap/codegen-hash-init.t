# ABOUTME: Tests that hash literal initializers survive codegen round-trip.
# ABOUTME: Regression test for #693 where my %h = (key => value, ...) was dropped.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPerlHelpers qw(setup_perl_grammar parse_and_generate eval_module);

my $gen_grammar = setup_perl_grammar('Chalk::Grammar::Perl::HashInitTest');
ok(defined $gen_grammar, 'grammar setup');

# ============================================================
# Test 1: simple hash literal initializer
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
use utf8;
class HashInitBasic {
    my %lookup = ('a' => 1, 'b' => 2);
    sub get($key) { return $lookup{$key} }
}
PERL

    # Write source to temp file
    my $tmpfile = '/tmp/hash-init-test-basic.pm';
    open my $fh, '>:utf8', $tmpfile or die $!;
    print $fh $source;
    close $fh;

    # The old Perl target does not emit a class-scope lexical; it refuses by
    # name rather than drop the initializer (the regression this file pinned).
    my $code = eval { parse_and_generate($gen_grammar, $tmpfile) };
    like($@, qr/GAP: a class-scope lexical/, 'hash init: refused by name, not dropped');

    unlink $tmpfile;
}

# ============================================================
# Test 2: hash init with qw() values (KeywordTable pattern)
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
use utf8;
class HashInitQW {
    my %rules = ('class' => [qw(ClassBlock)], 'sub' => [qw(SubDef)]);
    sub get($key) { return $rules{$key} }
}
PERL

    my $tmpfile = '/tmp/hash-init-test-qw.pm';
    open my $fh, '>:utf8', $tmpfile or die $!;
    print $fh $source;
    close $fh;

    my $code = eval { parse_and_generate($gen_grammar, $tmpfile) };
    like($@, qr/GAP: a class-scope lexical/, 'qw hash init: refused by name, not dropped');

    unlink $tmpfile;
}

done_testing();
