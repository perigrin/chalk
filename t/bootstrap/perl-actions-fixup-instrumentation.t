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

subtest 'fixup_counts() records any bumped fixup name' => sub {
    Chalk::Bootstrap::Perl::Actions->reset_fixup_counts();

    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_some_fixup');
    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_some_fixup');

    my $counts = Chalk::Bootstrap::Perl::Actions->fixup_counts();
    is($counts->{_some_fixup}, 2, '_some_fixup fired twice');
    ok(!exists $counts->{_fix_postfix_chain}, 'retired fixup not present');
};

subtest 'reset_fixup_counts() clears all entries' => sub {
    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_some_fixup');
    Chalk::Bootstrap::Perl::Actions->reset_fixup_counts();
    is_deeply(Chalk::Bootstrap::Perl::Actions->fixup_counts(), {},
        'counts empty after reset');
};

subtest 'known_fixups() is empty when no fixups are registered' => sub {
    # All disambiguation fixups have been deleted. The known_fixups registry
    # should be empty until new fixups are added.
    my %known = Chalk::Bootstrap::Perl::Actions->known_fixups()->%*;
    is(scalar keys %known, 0, 'no known fixups registered');
};

done_testing;
