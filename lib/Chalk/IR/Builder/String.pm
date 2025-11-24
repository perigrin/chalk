# ABOUTME: String and module operation builder methods for IR construction
# ABOUTME: Defines methods in Chalk::IR::Builder namespace for string/range/use nodes

use 5.42.0;
use experimental qw(class builtin);

use Chalk::IR::Node::StrConcat;

class Chalk::IR::Builder::String {

    # String operations (Issue #98 Phase 4)
    method build_str_concat_node($builder, $left_node, $right_node) {
        # Create StrConcat node for concatenating two strings
        my $node_id    = $builder->next_node_id();
        my $str_concat = Chalk::IR::Node::StrConcat->new(
            id         => $node_id,
            inputs     => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id    => $left_node->id,
            right_id   => $right_node->id,
        );
        $builder->graph->add_node($str_concat);

        # Record transformation
        $str_concat->record_transform(
            'ir_construction',
            'Builder::build_str_concat_node',
            context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id
        );

        return $str_concat;
    }

    # Range operations (Issue #111)
    method build_range_node($builder, $start_node, $end_node, $type = 'list') {
        # Create Range node for generating a range between start and end values
        my $start_ref = { op => 'NodeRef', node_id => $start_node->id };
        my $end_ref   = { op => 'NodeRef', node_id => $end_node->id };

        my $attributes = {
            start => $start_ref,
            end   => $end_ref,
            type  => $type,
        };

        my $node_id = $builder->next_node_id();
        my $range   = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'Range',
            inputs     => [ $builder->current_control, $start_node->id, $end_node->id ],
            attributes => $attributes,
        );
        $builder->graph->add_node($range);

        # Record transformation
        $range->record_transform(
            'ir_construction',
            'Builder::build_range_node',
            context => "start_id="
              . $start_node->id
              . ", end_id="
              . $end_node->id
              . ", type=$type"
        );

        return $range;
    }

    method build_str_length_node($builder, $string_node) {
        # Create StrLength node for getting string length
        my $string_ref = { op => 'NodeRef', node_id => $string_node->id };

        my $attributes = { string => $string_ref };

        my $node_id    = $builder->next_node_id();
        my $str_length = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'StrLength',
            inputs     => [ $builder->current_control, $string_node->id ],
            attributes => $attributes,
        );
        $builder->graph->add_node($str_length);

        # Record transformation
        $str_length->record_transform(
            'ir_construction',
            'Builder::build_str_length_node',
            context => "string_id=" . $string_node->id
        );

        return $str_length;
    }

    method build_str_substr_node($builder, $string_node, $offset_node, $length_node) {
        # Create StrSubstr node for extracting substring
        my $string_ref = { op => 'NodeRef', node_id => $string_node->id };
        my $offset_ref = { op => 'NodeRef', node_id => $offset_node->id };
        my $length_ref = { op => 'NodeRef', node_id => $length_node->id };

        my $attributes = {
            string => $string_ref,
            offset => $offset_ref,
            length => $length_ref
        };

        my $node_id    = $builder->next_node_id();
        my $str_substr = Chalk::IR::Node->new(
            id     => $node_id,
            op     => 'StrSubstr',
            inputs => [
                $builder->current_control, $string_node->id,
                $offset_node->id, $length_node->id
            ],
            attributes => $attributes,
        );
        $builder->graph->add_node($str_substr);

        # Record transformation
        $str_substr->record_transform(
            'ir_construction',
            'Builder::build_str_substr_node',
            context => "string_id="
              . $string_node->id
              . ", offset_id="
              . $offset_node->id
              . ", length_id="
              . $length_node->id
        );

        return $str_substr;
    }

    # Module system support (Issue #98 Phase 5)
    method build_use_statement_node($builder, $type, $module, $imports) {
      # Create UseStatement node for capturing use statement metadata
      # $type: 'version', 'pragma', 'module', or 'external'
      # $module: module name (e.g., '5.42.0', 'experimental', 'Chalk::IR::Node')
      # $imports: arrayref of imported symbols (empty for full import)

        my $attributes = {
            type    => $type,
            module  => $module,
            imports => $imports
        };

        my $node_id  = $builder->next_node_id();
        my $use_stmt = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'UseStatement',
            inputs     => [$builder->current_control],
            attributes => $attributes,
        );
        $builder->graph->add_node($use_stmt);

        # Record transformation
        my $import_list = join( ", ", $imports->@* );
        $use_stmt->record_transform(
            'ir_construction',
            'Builder::build_use_statement_node',
            context => "type=$type, module=$module, imports=[$import_list]"
        );

        return $use_stmt;
    }
}

1;
