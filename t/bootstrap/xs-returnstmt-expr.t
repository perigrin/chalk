# ABOUTME: Tests XS emission of ReturnStmt used as an expression (stale-value merge pattern).
# ABOUTME: Verifies ReturnStmt nodes are unwrapped when used in expression context.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::XS;

# Reset node factory
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $nf = Chalk::Bootstrap::IR::NodeFactory->instance();

# Build a method that returns SubscriptExpr(ReturnStmt($var), key, style)
# This reproduces the stale-value merge pattern from Earley.pm
# Pattern: return $chart->[$pos][$core_id][$origin]
# Stale-value IR: SubscriptExpr(SubscriptExpr(SubscriptExpr(ReturnStmt($chart), $pos, array), $core_id, array), $origin, array)

my $chart_var = $nf->make('Constant', value => '$chart', const_type => 'variable');
my $pos_var   = $nf->make('Constant', value => '$pos',   const_type => 'variable');
my $core_id   = $nf->make('Constant', value => '$core_id', const_type => 'variable');
my $origin    = $nf->make('Constant', value => '$origin', const_type => 'variable');
my $array_str = $nf->make('Constant', value => 'array',  const_type => 'string');

# Build the ReturnStmt-wrapped subscript chain
my $return_chart = $nf->make('Constructor', class => 'ReturnStmt', value => $chart_var);
my $sub1 = $nf->make('Constructor', class => 'SubscriptExpr', target => $return_chart, index => $pos_var, style => $array_str);
my $sub2 = $nf->make('Constructor', class => 'SubscriptExpr', target => $sub1, index => $core_id, style => $array_str);
my $sub3 = $nf->make('Constructor', class => 'SubscriptExpr', target => $sub2, index => $origin, style => $array_str);

# Wrap in a return statement for the method body
my $return_stmt = $nf->make('Constructor', class => 'ReturnStmt', value => $sub3);

# Build a MethodDecl
my $method_name = $nf->make('Constant', value => 'test_method', const_type => 'string');
my $chart_param = $nf->make('Constant', value => '$chart', const_type => 'variable');
my $pos_param   = $nf->make('Constant', value => '$pos',   const_type => 'variable');
my $core_param  = $nf->make('Constant', value => '$core_id', const_type => 'variable');
my $orig_param  = $nf->make('Constant', value => '$origin', const_type => 'variable');

my $method = $nf->make('Constructor', class => 'MethodDecl',
    name => $method_name,
    params => [$chart_param, $pos_param, $core_param, $orig_param],
    body => [$return_stmt],
);

# Create XS target and emit
my $xs_target = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::ReturnExpr',
);

my $lines = $xs_target->_emit_xs_method($method);
my $xs_output = join("\n", $lines->@*);

# The XS output should NOT contain NULL /* unsupported */
unlike($xs_output, qr/NULL \/\* unsupported \*\//, 'ReturnStmt-as-expression does not produce NULL');
unlike($xs_output, qr/\/\* unknown node \*\//, 'no unknown node markers');

# It should contain av_fetch for the subscript chain
like($xs_output, qr/av_fetch/, 'contains av_fetch for array subscript');

# It should reference chart parameter
like($xs_output, qr/chart/, 'references chart variable');

diag "Generated XS:\n$xs_output";

done_testing();
