#!/usr/bin/env perl
# ABOUTME: DEVIATES is a third L: verdict for output that is legal Perl but not perl's.
# ABOUTME: Its contract is STRICTER than GREEN: it must lower, run, and match a declared string.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::CodeGen::Harness::MdtestCorpus;

# ---------------------------------------------------------------------------
# WHY A THIRD VERDICT
#
# The gate compares chalk's stdout to perl's with exact string equality. That
# is the right default and it is not always a well-defined target, because
# `perl` is not self-consistent about numeric representation:
#
#     literal 9007199254740993  ->  9007199254740993
#     2**53 + 1                 ->  9.00719925474099e+15
#     numerically equal?           YES
#     string equal?                NO
#
# Same value, two outputs, both correct Perl. Perl-the-LANGUAGE does not
# specify IV vs NV, and a program cannot observe which was used except through
# B::, which is introspection of the implementation.
#
# So a static compiler with no runtime may legitimately produce a different
# STRING for the same VALUE. `DEVIATES` records exactly that, and its contract
# is STRICTER than GREEN rather than looser -- see the subtests.
#
# THE RULE THAT DECIDES WHAT MAY USE IT (perigrin): a deviation is legitimate
# when static compilation CANNOT do what perl does, and illegitimate when chalk
# simply HAS NOT YET. The second kind is a defect wearing a legitimising label,
# and the reason string is where that distinction is made explicit.
# ---------------------------------------------------------------------------

sub verdict ($ir) {
    return Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir);
}

subtest 'the existing two verdicts still parse' => sub {
    is verdict("%a = Start()\nL: GREEN\n"), 'GREEN', 'GREEN parses';
    is verdict("%a = Start()\nL: GAP(no lowering for op=Frobnicate)\n"), 'GAP',
        'GAP parses';
    is verdict("%a = Start()\n"), 'GREEN', 'absent L: defaults to GREEN';
};

subtest 'DEVIATES parses as its own verdict' => sub {
    my $ir = qq{%a = Start()\nL: DEVIATES(Perl does not specify IV vs NV) expected=9.00719925474099e+15\n};
    is verdict($ir), 'DEVIATES', 'DEVIATES is not folded into GREEN or GAP';
};

subtest 'DEVIATES carries a reason and an expected string' => sub {
    my $ir = qq{%a = Start()\nL: DEVIATES(hash order is randomised per process) expected=b,a,c\n};
    my $d = Chalk::CodeGen::Harness::MdtestCorpus->parse_deviation_from_ir($ir);

    ok defined $d, 'a DEVIATES line yields a deviation record';
    is $d->{expected}, 'b,a,c', 'the declared output is extracted verbatim';
    like $d->{reason}, qr/randomised/, 'the reason is extracted';
};

subtest 'a DEVIATES line without an expected string is REJECTED' => sub {
    # THE POINT OF THE VERDICT is that the output is pinned to something a
    # human wrote down. Without `expected=` there is nothing to check against,
    # and the case would silently accept any output at all -- strictly worse
    # than GREEN. That must be an error, not a default.
    my $ir = qq{%a = Start()\nL: DEVIATES(some reason)\n};
    my $err = do {
        local $@;
        eval { Chalk::CodeGen::Harness::MdtestCorpus->parse_deviation_from_ir($ir) };
        $@;
    };
    like $err, qr/expected=/,
        'a DEVIATES without expected= dies naming what is missing';
};

subtest 'a DEVIATES line without a reason is REJECTED' => sub {
    # The reason is where "cannot" is distinguished from "has not yet". A
    # deviation with no stated Perl-level justification is the failure mode
    # this verdict exists to prevent, so an empty reason cannot be legal.
    my $ir = qq{%a = Start()\nL: DEVIATES() expected=x\n};
    my $err = do {
        local $@;
        eval { Chalk::CodeGen::Harness::MdtestCorpus->parse_deviation_from_ir($ir) };
        $@;
    };
    like $err, qr/reason/i,
        'a DEVIATES with an empty reason dies naming what is missing';
};

subtest 'parse_deviation_from_ir returns undef for the other verdicts' => sub {
    is Chalk::CodeGen::Harness::MdtestCorpus
        ->parse_deviation_from_ir("%a = Start()\nL: GREEN\n"), undef,
        'GREEN has no deviation record';
    is Chalk::CodeGen::Harness::MdtestCorpus
        ->parse_deviation_from_ir("%a = Start()\nL: GAP(x)\n"), undef,
        'GAP has no deviation record';
};

done_testing;
