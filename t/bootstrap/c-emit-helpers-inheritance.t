# ABOUTME: Tests that Target::C inherits from EmitHelpers and shared helpers work via inheritance.
# ABOUTME: Verifies the refactoring that extracted shared helper methods from C.pm to EmitHelpers.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

# Test 1: EmitHelpers module loads without error
use_ok('Chalk::Bootstrap::Perl::Target::EmitHelpers');

# Test 2: Target::C loads without error (it should inherit from EmitHelpers)
use_ok('Chalk::Bootstrap::Perl::Target::C');

# Test 3: Target::C is a subclass of EmitHelpers
{
    my $target = eval {
        Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Some::Module')
    };
    ok(defined $target, 'Target::C can be constructed');
    isa_ok($target, 'Chalk::Bootstrap::Perl::Target::EmitHelpers',
        'Target::C is a subclass of EmitHelpers');
}

# Test 4: Shared helper methods are accessible on a Target::C instance
# These methods should be inherited from EmitHelpers
{
    my $target = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::Module');
    ok($target->can('_escape_c_string'),                 '_escape_c_string is available');
    ok($target->can('_wrap_retval'),                     '_wrap_retval is available');
    ok($target->can('_class_slug'),                      '_class_slug is available');
    ok($target->can('_find_mop_class'),                  '_find_mop_class is available');
    ok($target->can('_build_field_index_map'),           '_build_field_index_map is available');
    ok($target->can('_build_cfg_lookup'),                '_build_cfg_lookup is available');
    ok($target->can('_scan_class_methods'),              '_scan_class_methods is available');
    ok($target->can('_needs_eval_fallback'),             '_needs_eval_fallback is available');
    ok($target->can('_calls_uncompiled_my_subs'),        '_calls_uncompiled_my_subs is available');
    ok($target->can('_uses_class_scope_vars'),           '_uses_class_scope_vars is available');
    ok($target->can('_is_stale_merge'),                  '_is_stale_merge is available');
    ok($target->can('_repair_stale_merge'),              '_repair_stale_merge is available');
    ok($target->can('_field_sigil_for_expr'),            '_field_sigil_for_expr is available');
    ok($target->can('_fixup_xs_list_destructuring'),     '_fixup_xs_list_destructuring is available');
    ok($target->can('_fixup_ternary_assignment'),        '_fixup_ternary_assignment is available');
    ok($target->can('_fixup_filtercomposite_add_destructuring'),
        '_fixup_filtercomposite_add_destructuring is available');
    ok($target->can('_is_complex_method'),               '_is_complex_method is available');
    ok($target->can('_has_early_return'),                '_has_early_return is available');
    ok($target->can('_body_contains_return'),            '_body_contains_return is available');
    ok($target->can('_body_contains_bare_return'),       '_body_contains_bare_return is available');
    ok($target->can('_is_bare_return_expr'),             '_is_bare_return_expr is available');
    ok($target->can('_is_unambiguous_value_expr'),       '_is_unambiguous_value_expr is available');
    ok($target->can('_is_single_stmt_return_expr'),      '_is_single_stmt_return_expr is available');
    ok($target->can('_collect_var_decls'),               '_collect_var_decls is available');
    ok($target->can('_collect_all_var_refs'),            '_collect_all_var_refs is available');
    ok($target->can('_ir_default_to_perl'),              '_ir_default_to_perl is available');
    ok($target->can('emit_cfg_if'),                      'emit_cfg_if is available');
    ok($target->can('emit_cfg_phi_if'),                  'emit_cfg_phi_if is available');
    ok($target->can('emit_cfg_loop'),                    'emit_cfg_loop is available');
    ok($target->can('emit_cfg_try_catch'),               'emit_cfg_try_catch is available');
    ok($target->can('emit_from_cfg_state'),              'emit_from_cfg_state is available');
    ok($target->can('_find_exists_delete_in_chain'),     '_find_exists_delete_in_chain is available');
    ok($target->can('_build_exists_delete_native'),      '_build_exists_delete_native is available');
}

# Test 5: _escape_c_string works correctly (behavior test for an inherited method)
{
    my $target = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::Module');
    is($target->_escape_c_string('hello'),       'hello',        '_escape_c_string: plain string unchanged');
    is($target->_escape_c_string("a\nb"),        'a\\nb',        '_escape_c_string: newline escaped');
    is($target->_escape_c_string('a"b'),         'a\\"b',        '_escape_c_string: double quote escaped');
    is($target->_escape_c_string("a\tb"),        'a\\tb',        '_escape_c_string: tab escaped');
    is($target->_escape_c_string('a\\b'),        'a\\\\b',       '_escape_c_string: backslash escaped');
}

# Test 6: _class_slug works correctly (behavior test)
{
    my $target = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::Module');
    is($target->_class_slug('Chalk::Bootstrap::Earley'), 'earley',   '_class_slug: qualified name');
    is($target->_class_slug('Boolean'),                  'boolean',  '_class_slug: simple name');
    is($target->_class_slug('SlugTest'),                 'slugtest', '_class_slug: camel case');
}

# Test 7: _wrap_retval works correctly (behavior test)
{
    my $target = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::Module');
    is($target->_wrap_retval('newSViv(42)'),       'newSViv(42)',             '_wrap_retval: newSV* unchanged');
    is($target->_wrap_retval('&PL_sv_yes'),        '&PL_sv_yes',             '_wrap_retval: PL_sv_* unchanged');
    is($target->_wrap_retval('SvREFCNT_inc(foo)'), 'SvREFCNT_inc(foo)',      '_wrap_retval: already inc unchanged');
    is($target->_wrap_retval('sv_setsv(a, b)'),    'sv_setsv(a, b)',         '_wrap_retval: sv_setsv unchanged');
    is($target->_wrap_retval('some_sv'),           'SvREFCNT_inc(some_sv)', '_wrap_retval: plain var gets inc');
}

# Test 8: _needs_eval_fallback works correctly
{
    my $target = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::Module');
    is($target->_needs_eval_fallback('clean code here'),       false, '_needs_eval_fallback: clean code');
    is($target->_needs_eval_fallback('NULL /* unsupported */'), true, '_needs_eval_fallback: unsupported marker');
    is($target->_needs_eval_fallback('/* unknown node */'),     true, '_needs_eval_fallback: unknown node');
}

# Test 9: _find_mop_class picks the non-main class from a MOP.
{
    use Chalk::MOP;
    my $mop = Chalk::MOP->new;
    $mop->declare_class('Some::Class');  # plus 'main' which is auto-declared

    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Some::Class',
    );
    my $cls = $target->_find_mop_class($mop);
    ok(defined $cls, '_find_mop_class returns a class');
    is($cls->name, 'Some::Class', '_find_mop_class returns the non-main class');
}

done_testing;
