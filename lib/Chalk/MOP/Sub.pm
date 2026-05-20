# ABOUTME: Compile-time metaobject for a subroutine declaration within a class.
# ABOUTME: Distinguished from Method by having no implicit $self and no method dispatch.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Graph;

class Chalk::MOP::Sub {
    field $name        :param :reader;
    field $class       :param :reader;
    field $params      :param :reader = [];
    field $return_type :param :reader = undef;
    field $graph       :param :reader = Chalk::IR::Graph->new;
    field $body        :param :reader = [];

    # Delegate node construction to this sub's graph.
    # Hash-cons scope is per-graph, so identical content across subs yields
    # distinct node objects and consumer lists stay bounded to this sub.
    method merge($node)  { $graph->merge($node) }
    method next_cfg_id() { $graph->next_cfg_id }
}
