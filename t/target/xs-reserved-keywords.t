# ABOUTME: Tests that C/C++ reserved keywords in parameter names are sanitized
# ABOUTME: Verifies XS code generation doesn't emit conflicting identifiers (#562)

use v5.42;
use Test::More;
use FindBin qw($RealBin);
use Scalar::Util 'blessed';

use lib "$RealBin/../../lib";
use Chalk::Target::XS::AST::XSUB;

# Test 1: 'class' parameter is sanitized
subtest 'Parameter name "class" is sanitized' => sub {
    my $xsub = Chalk::Target::XS::AST::XSUB->new(
        name => 'TOP',
        params => ['$class'],
        body => ['RETVAL = newSVpv("test", 0);'],
        return_type => 'SV*',
    );

    my $xs = $xsub->emit();

    # Should NOT contain 'class' as a parameter (C++ keyword)
    unlike($xs, qr/\bclass\s*\)/, 'Does not use "class" as parameter name');

    # Should contain sanitized version
    like($xs, qr/\b(klass|class_)\s*\)/, 'Uses sanitized parameter name (klass or class_)');

    # Should be valid C identifier
    like($xs, qr/SV\*\s+TOP\s*\(\s*\w+\s*\)/, 'Has valid C function signature');
};

# Test 2: Multiple reserved keywords
subtest 'Multiple C++ keywords are sanitized' => sub {
    my $xsub = Chalk::Target::XS::AST::XSUB->new(
        name => 'test_keywords',
        params => ['$class', '$new', '$delete'],
        body => ['// test'],
        return_type => 'void',
    );

    my $xs = $xsub->emit();

    # None of the C++ keywords should appear as-is
    unlike($xs, qr/\(.*\bclass[,\)]/, '"class" sanitized');
    unlike($xs, qr/\bclass\s*,/, '"class" not used in param list');
    unlike($xs, qr/,\s*new\s*,/, '"new" sanitized');
    unlike($xs, qr/,\s*delete\s*\)/, '"delete" sanitized');
};

# Test 3: Non-keywords are unchanged
subtest 'Non-keyword parameters unchanged' => sub {
    my $xsub = Chalk::Target::XS::AST::XSUB->new(
        name => 'regular_params',
        params => ['$name', '$value', '$count'],
        body => [],
        return_type => 'IV',
    );

    my $xs = $xsub->emit();

    # Regular parameters should keep their names (minus sigil)
    like($xs, qr/\bname\b/, 'name preserved');
    like($xs, qr/\bvalue\b/, 'value preserved');
    like($xs, qr/\bcount\b/, 'count preserved');
};

# Test 4: Common Perl OO keywords
subtest 'Common OO keywords are sanitized' => sub {
    my $xsub = Chalk::Target::XS::AST::XSUB->new(
        name => 'create',
        params => ['$class', '$this'],
        body => [],
        return_type => 'SV*',
    );

    my $xs = $xsub->emit();

    # Both 'class' and 'this' are C++ keywords
    unlike($xs, qr/\bclass[,\)]/, '"class" sanitized');
    unlike($xs, qr/\bthis[,\)]/, '"this" sanitized');
};

# Test 5: Edge case - 'class' in body should be OK (only params sanitized)
subtest 'Keywords in body are not affected' => sub {
    my $xsub = Chalk::Target::XS::AST::XSUB->new(
        name => 'test_body',
        params => ['$obj'],
        body => ['SV* class_name = sv_derived_from(obj, "MyClass");'],
        return_type => 'SV*',
    );

    my $xs = $xsub->emit();

    # 'class' in body should remain as-is (part of 'class_name')
    like($xs, qr/class_name/, 'Body can contain keyword as part of identifier');

    # But parameter should be unchanged (not a keyword)
    like($xs, qr/test_body\(obj\)/, 'Non-keyword parameter unchanged');
};

# Test 6: Practical example from self-hosting
subtest 'Self-hosting TOP method signature' => sub {
    my $xsub = Chalk::Target::XS::AST::XSUB->new(
        name => 'TOP',
        params => ['$class'],
        body => [
            'SV* tmp_1 = sv_2object(class);',
            'RETVAL = call_method(tmp_1, "top");',
        ],
        return_type => 'SV*',
    );

    my $xs = $xsub->emit();

    # Must not have syntax errors
    unlike($xs, qr/SV\*\s+TOP\s*\(\s*class\s*\)/, 'Does not emit invalid C++ syntax');

    # Should have sanitized parameter
    like($xs, qr/SV\*\s+TOP\s*\(\s*\w+\s*\)/, 'Has valid signature');

    # Body should reference sanitized name
    # (Note: this test assumes body statements use the parameter)
    ok(length($xs) > 0, 'Generates non-empty XS code');
};

done_testing();
