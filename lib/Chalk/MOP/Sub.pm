# ABOUTME: Compile-time metaobject for a subroutine declaration within a class.
# ABOUTME: Distinguished from Method by having no implicit $self and no method dispatch.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;

class Chalk::MOP::Sub {
    field $name        :param :reader;
    field $class       :param :reader;
    field $params      :param :reader = [];
    field $return_type :param :reader = undef;
    field $graph       :param :reader = Chalk::IR::Graph->new;
    field $factory     :param :reader = Chalk::IR::NodeFactory->new;
    field $body        :param :reader = [];

    # Delegate graph operations to this sub's $graph. See MOP::Method
    # for rationale: $graph is per-sub (honest); $factory is currently
    # unused scaffolding so there are no make/make_cfg delegators.
    method merge($node)  { $graph->merge($node) }
    method next_cfg_id() { $graph->next_cfg_id }
}
