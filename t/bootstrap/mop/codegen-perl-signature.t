# ABOUTME: Tests Target::Perl::generate($mop) returns HashRef[Str].
# ABOUTME: Per Phase 4, codegen accepts a MOP and emits a per-file hashref.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed reftype);
use lib 'lib';

use Chalk::MOP;
use Chalk::Bootstrap::Perl::Target::Perl;

# generate($mop) must exist as a method on Target::Perl
ok(Chalk::Bootstrap::Perl::Target::Perl->can('generate'),
    'Target::Perl has a generate method');

# It must accept a Chalk::MOP and return a HashRef[Str].
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Empty');

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $result = $target->generate($mop);

    ok(defined $result, 'generate($mop) returns a defined value');
    is(reftype($result), 'HASH',
        'generate($mop) returns a hashref');

    SKIP: {
        skip 'no hashref to inspect', 1 unless reftype($result // '') eq 'HASH';
        # Every value should be a defined non-empty string (the per-file
        # generated source). Pass an empty file set as a degenerate case;
        # the hash may be empty, but if any keys exist they must map to strs.
        my @bad = grep { ref($result->{$_}) || !defined $result->{$_} }
            keys $result->%*;
        is(scalar @bad, 0,
            'generate($mop) values are plain (non-ref, defined) strings')
            or diag('non-string keys: ' . join(',', @bad));
    }
}

done_testing();
