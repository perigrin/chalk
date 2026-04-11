# ABOUTME: Tests that 'no' pragma declarations survive codegen round-trip.
# ABOUTME: Regression test for 'no warnings' being emitted as function call no(...).
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPerlHelpers qw(setup_perl_grammar parse_and_generate eval_module);

my $gen_grammar = setup_perl_grammar('Chalk::Grammar::Perl::NoPragmaTest');
ok(defined $gen_grammar, 'grammar setup');

# ============================================================
# Test 1: no warnings 'experimental::class'
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';
class Foo {
    method bar() { return 42; }
}
PERL

    my $tmpfile = '/tmp/codegen-no-pragma-test.pm';
    open my $fh, '>:utf8', $tmpfile or die $!;
    print $fh $source;
    close $fh;

    my $code = parse_and_generate($gen_grammar, $tmpfile);
    ok(defined $code, 'no pragma: generates code');

    SKIP: {
        skip 'no generated code', 3 unless defined $code;

        like($code, qr/^no\s+warnings/m, 'no pragma: emits "no warnings"');
        unlike($code, qr/no\(/, 'no pragma: not emitted as function call no(...)');

        TODO: {
            local $TODO = 'eval may not fully support class keyword in string eval context';
            my ($ok, $err) = eval_module($code, 'Foo', 'Foo::NoPragmaTest');
            ok($ok, 'no pragma: evals cleanly') or diag("Error: $err");
        }
    }

    unlink $tmpfile;
}

# ============================================================
# Test 2: no strict 'refs'
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
use utf8;
class Bar {
    sub test() {
        no strict 'refs';
        return 1;
    }
}
PERL

    my $tmpfile = '/tmp/codegen-no-strict-test.pm';
    open my $fh, '>:utf8', $tmpfile or die $!;
    print $fh $source;
    close $fh;

    my $code = parse_and_generate($gen_grammar, $tmpfile);
    ok(defined $code, 'no strict: generates code');

    SKIP: {
        skip 'no generated code', 1 unless defined $code;
        like($code, qr/no\s+strict/m, 'no strict: emits "no strict"');
    }

    unlink $tmpfile;
}

done_testing();
