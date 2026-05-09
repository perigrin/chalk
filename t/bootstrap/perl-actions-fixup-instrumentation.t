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

    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_fix_postfix_chain');
    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_fix_postfix_chain');
    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_push_deref_inward');

    my $counts = Chalk::Bootstrap::Perl::Actions->fixup_counts();
    is($counts->{_fix_postfix_chain}, 2, '_fix_postfix_chain fired twice');
    is($counts->{_push_deref_inward}, 1, '_push_deref_inward fired once');
    ok(!exists $counts->{_fix_postfix_chain_deep}, 'unfired fixups not present');
};

subtest 'reset_fixup_counts() clears all entries' => sub {
    Chalk::Bootstrap::Perl::Actions->_bump_fixup('_fix_postfix_chain');
    Chalk::Bootstrap::Perl::Actions->reset_fixup_counts();
    is_deeply(Chalk::Bootstrap::Perl::Actions->fixup_counts(), {},
        'counts empty after reset');
};

subtest 'instrumented fixup names cover all five disambiguation fixups' => sub {
    # The known disambiguation fixups in Actions.pm. As filtering-stack work
    # retires each ambiguity class, the corresponding fixup gets deleted and
    # the entry should be removed from this list.
    my @expected = qw(
        _fix_postfix_chain
        _fix_postfix_chain_deep
        _push_deref_inward
        _push_methodcall_inward
        _fixup_stmts
    );

    my %known = Chalk::Bootstrap::Perl::Actions->known_fixups()->%*;
    for my $name (@expected) {
        ok($known{$name}, "fixup $name is registered as known");
    }
};

done_testing;
