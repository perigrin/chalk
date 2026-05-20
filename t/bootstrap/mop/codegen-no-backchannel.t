# ABOUTME: Tests that Target::Perl and Target::C have no methods taking ($sa, $ctx) args.
# ABOUTME: Per Phase 4, the SA/Context backchannel is removed from the public codegen API.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Bootstrap::Perl::Target::Perl;
use Chalk::Bootstrap::Perl::Target::C;

# After Phase 4, the legacy entry points generate_with_cfg(\$ir, \$sa,
# \$ctx) on Target::Perl and generate_c_files(\$ir, \$sa, \$ctx) on
# Target::C must be removed. The public surface is generate(\$mop).
ok(!Chalk::Bootstrap::Perl::Target::Perl->can('generate_with_cfg'),
    'Target::Perl::generate_with_cfg removed');
ok(!Chalk::Bootstrap::Perl::Target::C->can('generate_c_files'),
    'Target::C::generate_c_files removed');

done_testing();
