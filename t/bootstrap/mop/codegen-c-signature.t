# ABOUTME: Tests Target::C::generate($mop) returns HashRef[Str] with .c and .xs entries.
# ABOUTME: Per Phase 4, the C target accepts a MOP and emits both .c and .xs files.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(reftype);
use lib 'lib';

use Chalk::MOP;
use Chalk::Bootstrap::Perl::Target::C;

# generate($mop) must exist as a method on Target::C.
ok(Chalk::Bootstrap::Perl::Target::C->can('generate'),
    'Target::C has a generate method');

# It must accept a Chalk::MOP and return a HashRef[Str] with at least
# one .c and one .xs file when the MOP has a class with a method.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Tiny');
    $cls->declare_method('noop', params => []);

    my $target = Chalk::Bootstrap::Perl::Target::C->new;
    my $result = $target->generate($mop);

    ok(defined $result, 'generate($mop) returns a defined value');
    is(reftype($result), 'HASH',
        'generate($mop) returns a hashref');

    SKIP: {
        skip 'no hashref to inspect', 2
            unless reftype($result // '') eq 'HASH';

        my @keys = keys $result->%*;
        ok(scalar(grep { /\.c$/ } @keys) >= 1,
            'hashref has at least one .c entry')
            or diag('keys: ' . join(',', @keys));
        ok(scalar(grep { /\.xs$/ } @keys) >= 1,
            'hashref has at least one .xs entry')
            or diag('keys: ' . join(',', @keys));
    }
}

done_testing();
