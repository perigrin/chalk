# ABOUTME: Verifies fixup instrumentation in Perl::Actions counts disambiguation-fixup fires.
# ABOUTME: Each fire is a parser-derivation correction; counts surface filter-stack incompleteness.
use 5.42.0;
use utf8;
use Test::More;
use Chalk::Bootstrap::Perl::Actions;

subtest 'fixup_counts() starts empty after reset' => sub {
    Chalk::Bootstrap::Perl::Actions->reset_fixup_counts();
    my $counts = Chalk::Bootstrap::Perl::Actions->fixup_counts();
    is(ref $counts, 'HASH', 'fixup_counts returns a hashref');
    is_deeply($counts, {}, 'counts are empty after reset');
};

subtest 'fixup_counts() records each instrumented fixup name' => sub {
    Chalk::Bootstrap::Perl::Actions->reset_fixup_counts();

    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_fixup_stmts');
    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_fixup_stmts');

    my $counts = Chalk::Bootstrap::Perl::Actions->fixup_counts();
    is($counts->{_fixup_stmts}, 2, '_fixup_stmts fired twice');
    ok(!exists $counts->{_fix_postfix_chain}, 'retired fixup not present');
};

subtest 'reset_fixup_counts() clears all entries' => sub {
    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_fixup_stmts');
    Chalk::Bootstrap::Perl::Actions->reset_fixup_counts();
    is_deeply(Chalk::Bootstrap::Perl::Actions->fixup_counts(), {},
        'counts empty after reset');
};

subtest 'instrumented fixup names cover all active disambiguation fixups' => sub {
    # The known disambiguation fixups in Actions.pm. As filtering-stack work
    # retires each ambiguity class, the corresponding fixup gets deleted and
    # the entry should be removed from this list.
    my @expected = qw(
        _fixup_stmts
    );

    my %known = Chalk::Bootstrap::Perl::Actions->known_fixups()->%*;
    for my $name (@expected) {
        ok($known{$name}, "fixup $name is registered as known");
    }
};

done_testing;
