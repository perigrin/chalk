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

    # Delegate node construction to this sub's graph and factory.
    # Hash-cons scope is per-graph (and after Phase 7b Stage 2, per-factory),
    # so identical content across subs yields distinct node objects and
    # consumer lists stay bounded to this sub.
    method merge($node)      { $graph->merge($node) }
    method make($op, %a)     { $factory->make($op, %a) }
    method make_cfg($op, %a) { $factory->make_cfg($op, %a) }
    method next_cfg_id()     { $graph->next_cfg_id }
}
