# ABOUTME: Compile-time metaobject for a method declaration within a class.
# ABOUTME: Owns the method's name, params, return type, and IR graph (with per-method hash-cons scope).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::VarDecl;

class Chalk::MOP::Method {
    field $name             :param :reader;
    field $class            :param :reader;
    field $params           :param :reader = [];
    field $return_type      :param :reader = undef;
    field $graph            :param :reader = Chalk::IR::Graph->new;
    field $factory          :param :reader = Chalk::IR::NodeFactory->new;
    field $body             :param :reader = [];
    field $lexical_bindings :param        = [];

    # Delegate node construction to this method's graph and factory.
    # Hash-cons scope is per-graph (and after Phase 7b Stage 2, per-factory),
    # so identical content across methods yields distinct node objects and
    # consumer lists stay bounded to this method.
    method merge($node)     { $graph->merge($node) }
    method make($op, %a)    { $factory->make($op, %a) }
    method make_cfg($op, %a) { $factory->make_cfg($op, %a) }
    method next_cfg_id()    { $graph->next_cfg_id }

    # Lexical bindings: VarDecl IR nodes declared in this method's body.
    # Returns the list (not the arrayref) so callers can scalar @list etc.
    method lexical_bindings() { return $lexical_bindings->@*; }
}
