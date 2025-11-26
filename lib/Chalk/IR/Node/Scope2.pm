# ABOUTME: Scope for SSA variable bindings (v2 rewrite)
# ABOUTME: Tracks variable->node mappings and current control
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Scope2 {
    field $bindings = {};
    field $current_control :reader;

    method set_current_control($ctrl) {
        $current_control = $ctrl;
    }

    method define($name, $node) {
        $bindings->{$name} = $node;
    }

    method get($name) {
        return $bindings->{$name};
    }

    method snapshot() {
        return {
            bindings => { %$bindings },
            control  => $current_control,
        };
    }

    method restore($snap) {
        $bindings = { $snap->{bindings}->%* };
        $current_control = $snap->{control};
    }

    method modified_vars($before_snapshot) {
        my @modified;
        for my $var (keys %$bindings) {
            my $before = $before_snapshot->{bindings}{$var};
            my $after = $bindings->{$var};
            if (!$before || $before->id ne $after->id) {
                push @modified, $var;
            }
        }
        return @modified;
    }
}

1;
