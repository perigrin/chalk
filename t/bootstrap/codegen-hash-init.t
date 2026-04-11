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

    my $code = parse_and_generate($gen_grammar, $tmpfile);
    ok(defined $code, 'hash init: generates code');

    SKIP: {
        skip 'no generated code', 2 unless defined $code;

        # The generated code should contain the initializer, not just 'my %lookup;'
        unlike($code, qr/my \%lookup;\s*$/m,
            'hash init: not an empty declaration');
        like($code, qr/my \%lookup\s*=/, 'hash init: has = initializer');
    }

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

    my $code = parse_and_generate($gen_grammar, $tmpfile);
    ok(defined $code, 'qw hash init: generates code');

    SKIP: {
        skip 'no generated code', 1 unless defined $code;
        like($code, qr/my \%rules\s*=/, 'qw hash init: has = initializer');
    }

    unlink $tmpfile;
}

done_testing();
