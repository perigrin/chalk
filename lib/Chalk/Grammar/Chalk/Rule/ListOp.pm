# ABOUTME: Semantic action for ListOp - list operations (map, grep, all, any)
# ABOUTME: Generates Map/Filter IR nodes for list comprehensions

use 5.42.0;
use experimental 'class';
use Scalar::Util 'blessed';

class Chalk::Grammar::Chalk::Rule::ListOp :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Map;
        use Chalk::IR::Node::Filter;
        use Chalk::IR::Node::Constant;
        use Chalk::Grammar::Chalk::Type::Str;

        # ListOp -> 'map' WS_OPT Block WS_OPT Expression
        # ListOp -> 'grep' WS_OPT Block WS_OPT Expression
        # ListOp -> 'all' WS_OPT Block WS_OPT Expression
        # ListOp -> 'any' WS_OPT Block WS_OPT Expression

        my @children = $context->children->@*;
        my $num_children = scalar(@children);

        # Get keyword (first child) to determine operation type
        my $keyword_child = $context->child(0);
        my $keyword;
        if (blessed($keyword_child) && $keyword_child->can('value')) {
            $keyword = $keyword_child->value;
        } elsif (defined($keyword_child)) {
            $keyword = "$keyword_child";
        } else {
            $keyword = 'unknown';
        }

        # Find block and list by scanning for IR nodes after keyword
        my $block;
        my $list;
        for my $i (1 .. $num_children - 1) {
            my $child = $context->child($i);
            next unless blessed($child) && $child->can('id');

            if (!defined($block)) {
                $block = $child;
            } else {
                $list = $child;
                last;
            }
        }

        # Wrap block as constant if not an IR node
        unless (defined($block) && blessed($block) && $block->can('id')) {
            $block = Chalk::IR::Node::Constant->new(
                value => 'block',
                type => Chalk::Grammar::Chalk::Type::Str->new(),
            );
        }

        # Wrap list as constant if not an IR node
        unless (defined($list) && blessed($list) && $list->can('id')) {
            $list = Chalk::IR::Node::Constant->new(
                value => 'list',
                type => Chalk::Grammar::Chalk::Type::Str->new(),
            );
        }

        # Generate appropriate node based on keyword
        if ($keyword eq 'map') {
            return Chalk::IR::Node::Map->new(
                block => $block,
                list  => $list,
            );
        }
        elsif ($keyword eq 'grep') {
            return Chalk::IR::Node::Filter->new(
                block => $block,
                list  => $list,
            );
        }
        else {
            # For 'all', 'any' - pass through for now (future enhancement)
            # Return a Map as placeholder
            return Chalk::IR::Node::Map->new(
                block => $block,
                list  => $list,
            );
        }
    }
}

1;
