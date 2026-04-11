# ABOUTME: Tests that builtins taking hash/array arguments emit correctly.
# ABOUTME: Regression test for keys/values/each/delete/exists with % and @ args.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPerlHelpers qw(setup_perl_grammar parse_and_generate);

my $gen_grammar = setup_perl_grammar('Chalk::Grammar::Perl::BuiltinHashTest');
ok(defined $gen_grammar, 'grammar setup');

# ============================================================
# Test 1: keys %hash
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
use utf8;
class KeysTest {
    my %h = ('a', 1, 'b', 2);
    sub get_keys() { return keys %h; }
}
PERL

    my $tmpfile = '/tmp/codegen-builtin-hash-test.pm';
    open my $fh, '>:utf8', $tmpfile or die $!;
    print $fh $source;
    close $fh;

    my $code = parse_and_generate($gen_grammar, $tmpfile);
    ok(defined $code, 'keys %hash: generates code');

    SKIP: {
        skip 'no generated code', 2 unless defined $code;

        like($code, qr/keys\s*[\(%]/, 'keys %hash: emits keys with hash arg');
        unlike($code, qr/'keys'\s*%\s*'h'/, 'keys %hash: not emitted as string modulo');
    }

    unlink $tmpfile;
}

# ============================================================
# Test 2: values %hash
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
use utf8;
class ValuesTest {
    my %h = ('a', 1);
    sub get_values() { return values %h; }
}
PERL

    my $tmpfile = '/tmp/codegen-builtin-values-test.pm';
    open my $fh, '>:utf8', $tmpfile or die $!;
    print $fh $source;
    close $fh;

    my $code = parse_and_generate($gen_grammar, $tmpfile);
    ok(defined $code, 'values %hash: generates code');

    SKIP: {
        skip 'no generated code', 1 unless defined $code;
        like($code, qr/values\s*[\(%]/, 'values %hash: emits values with hash arg');
    }

    unlink $tmpfile;
}

done_testing();
