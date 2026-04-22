# ABOUTME: Abstract base class for phaser metaobjects (lifecycle hooks with executable bodies).
# ABOUTME: Provides graph, source_position, and per-phaser node construction delegation.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Graph;

class Chalk::MOP::Phaser {
    field $graph           :param :reader = Chalk::IR::Graph->new;
    field $source_position :param :reader = 0;

    # Delegate node construction to this phaser's graph.
    # Hash-cons scope is per-graph, so identical content across phasers yields
    # distinct node objects and consumer lists stay bounded to this phaser.
    method merge($node)  { $graph->merge($node) }
    method next_cfg_id() { $graph->next_cfg_id }
}
