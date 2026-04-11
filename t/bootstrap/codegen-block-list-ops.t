# ABOUTME: Tests that map/grep/sort with block arguments emit correctly.
# ABOUTME: Regression test for #691 where block form collapsed to expr form.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPerlHelpers qw(setup_perl_grammar parse_and_generate eval_module);

my $gen_grammar = setup_perl_grammar('Chalk::Grammar::Perl::BlockListTest');
ok(defined $gen_grammar, 'grammar setup');

# ============================================================
# Test 1: map { BLOCK } @array
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
use utf8;
class MapBlockTest {
    sub test() {
        my @arr = (1, 2, 3);
        my @x = map { $_ + 1 } @arr;
        return @x;
    }
}
PERL

    my $tmpfile = '/tmp/codegen-map-block-test.pm';
    open my $fh, '>:utf8', $tmpfile or die $!;
    print $fh $source;
    close $fh;

    my $code = parse_and_generate($gen_grammar, $tmpfile);
    ok(defined $code, 'map block: generates code');

    SKIP: {
        skip 'no generated code', 2 unless defined $code;

        like($code, qr/map\s*\{/, 'map block: emits map { ... } form');
        unlike($code, qr/map\(/, 'map block: not emitted as map(...) expr form');
    }

    unlink $tmpfile;
}

# ============================================================
# Test 2: grep { BLOCK } @array
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
use utf8;
class GrepBlockTest {
    sub test() {
        my @arr = (1, 2, 3);
        my @x = grep { $_ > 1 } @arr;
        return @x;
    }
}
PERL

    my $tmpfile = '/tmp/codegen-grep-block-test.pm';
    open my $fh, '>:utf8', $tmpfile or die $!;
    print $fh $source;
    close $fh;

    my $code = parse_and_generate($gen_grammar, $tmpfile);
    ok(defined $code, 'grep block: generates code');

    SKIP: {
        skip 'no generated code', 1 unless defined $code;
        like($code, qr/grep\s*\{/, 'grep block: emits grep { ... } form');
    }

    unlink $tmpfile;
}

# ============================================================
# Test 3: sort { BLOCK } @array
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
use utf8;
class SortBlockTest {
    sub test() {
        my @arr = (3, 1, 2);
        my @x = sort { $a <=> $b } @arr;
        return @x;
    }
}
PERL

    my $tmpfile = '/tmp/codegen-sort-block-test.pm';
    open my $fh, '>:utf8', $tmpfile or die $!;
    print $fh $source;
    close $fh;

    my $code = parse_and_generate($gen_grammar, $tmpfile);
    ok(defined $code, 'sort block: generates code');

    SKIP: {
        skip 'no generated code', 1 unless defined $code;
        like($code, qr/sort\s*\{/, 'sort block: emits sort { ... } form');
    }

    unlink $tmpfile;
}

done_testing();
