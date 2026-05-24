# ABOUTME: Walks Perl IR (Program/UseDecl/ClassDecl/MethodDecl/etc) and emits Perl source.
# ABOUTME: Generates feature class code that is behaviorally equivalent to the original.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;
use Chalk::IR::Node;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::UnaryOp;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::AnonSub;
use Chalk::IR::Node::RegexMatch;
use Chalk::IR::Node::RegexSubst;
use Chalk::IR::Node::BacktickExpr;
use Chalk::IR::Node::Aggregate;
use Chalk::IR::Node::Regex;
use Chalk::IR::Node::TryCatch;
use Chalk::IR::Node::TernaryExpr;
use Chalk::IR::Node::StructRef;
use Chalk::IR::Node::StructFieldAccess;
use Chalk::IR::UseInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::UseInfo;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::UnaryOp;
use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::Program;
use Chalk::IR::Schedule;
use Chalk::IR::Schedule::Item;
use Chalk::IR::Scheduler::EagerPinning;
use Chalk::Scheduler::EagerPinning::If;
use Chalk::Scheduler::EagerPinning::Loop;
use Chalk::Scheduler::EagerPinning::TryCatch;

class Chalk::Bootstrap::Perl::Target::Perl :isa(Chalk::Bootstrap::Target) {

    # Lookup from IR node refaddr → cfg_state entry, built by _generate_with_cfg
    field %_cfg_lookup;

    # Struct schemas for StructRef/FieldAccess lowering (schema_name → { fields => [...] })
    field $_struct_schemas = {};

    # Set of variable base names declared with aggregate sigils (% or @).
    # Used by _emit_subscript_expr to emit $hash{key} instead of $hash->{key}
    # when the variable was declared as %hash.  Keys are bare names (no sigil).
    field %_aggregate_vars;

    # Set struct schemas for StructRef/FieldAccess lowering.
    method set_struct_schemas($schemas) {
        $_struct_schemas = $schemas;
    }

    # Public wrapper for _emit_expr (used by tests and external callers).
    method emit_expr($node) {
        return $self->_emit_expr($node);
    }

    # Polymorphic entry point. Accepts either:
    #   - Chalk::IR::Program: emits a single source-string (legacy path,
    #     kept alive transitionally for Target::C-via-Phase-7).
    #   - Chalk::MOP: emits a HashRef[Str] keyed by class-or-module name
    #     (production path, scheduler-driven as of Phase 5).
    #
    # The MOP path used to call _generate_from_mop, which walked the
    # MOP and synthesized legacy MethodInfo/ClassInfo wrappers so the
    # _emit_*_decl helpers could run unchanged. As of Phase 5b HANDOFF,
    # generate($mop) routes to _generate_from_schedule — the scheduler-
    # driven codegen that consumes Chalk::IR::Schedule directly. The
    # _generate_from_mop method stays alive in this commit so the
    # legacy byte-compat test (codegen-byte-compat.t) keeps running
    # against the old path for comparison; Phase 6 deletes it.
    method generate($input) {
        if (defined($input) && blessed($input) && $input isa Chalk::MOP) {
            return $self->_generate_from_schedule($input);
        }
        die "generate() requires a Program IR node or a Chalk::MOP"
            unless defined($input) && $input isa Chalk::IR::Program;

        return $self->_emit_program($input);
    }

    method _generate_from_mop($mop) {
        # Reproduce the legacy Program-shaped emit order: top-level
        # imports first (from `main`'s declared imports), then non-main
        # classes in declaration order, then top-level subs.
        # Output is a single entry under "main.pm" - the MOP holds the
        # content of one parse (one source file), so a single-string
        # value mirroring the legacy generate() return is the natural
        # shape.
        my @lines;

        my $main = $mop->for_class('main');
        if (defined $main) {
            for my $import ($main->imports) {
                my $use_info = Chalk::IR::UseInfo->new(
                    name => $import->module,
                    args => [$import->args],
                );
                push @lines, $self->_emit_use_decl($use_info);
            }
        }

        for my $cls ($mop->classes()) {
            my $name = $cls->name;
            next if $name eq 'main';

            # Reconstruct the ClassInfo body so _emit_class_decl can run.
            my @body;
            for my $field ($cls->fields) {
                my @attrs = map {
                    +{ name => ($_ =~ s/^://r), value => undef }
                } $field->attributes;
                push @body, Chalk::IR::FieldInfo->new(
                    name          => $field->name,
                    attributes    => \@attrs,
                    (defined $field->default_value
                        ? (default_value => $field->default_value)
                        : ()),
                );
            }
            for my $method ($cls->methods) {
                # Prefer the body arrayref stored on MOP::Method when
                # present; fall back to walking the graph for callers
                # that built the MOP without an explicit body. Walking
                # the chain misses non-VarDecl side-effects (e.g. a
                # bare `push @list, $x` statement) because Block's
                # control-chain fixup only rebuilds VarDecl/Return.
                my $body_ref = $method->body;
                my @method_body = (ref($body_ref) eq 'ARRAY' && $body_ref->@*)
                    ? $body_ref->@*
                    : $self->_body_from_graph($method->graph);
                push @body, Chalk::IR::MethodInfo->new(
                    name        => $method->name,
                    params      => $method->params,
                    return_type => $method->return_type,
                    body        => \@method_body,
                    graph       => $method->graph,
                );
            }
            for my $sub ($cls->subs) {
                my $body_ref = $sub->body;
                my @sub_body = (ref($body_ref) eq 'ARRAY' && $body_ref->@*)
                    ? $body_ref->@*
                    : $self->_body_from_graph($sub->graph);
                push @body, Chalk::IR::SubInfo->new(
                    name   => $sub->name,
                    params => $sub->params,
                    body   => \@sub_body,
                    graph  => $sub->graph,
                );
            }

            my $parent_name;
            if ($cls->can('superclass') && defined $cls->superclass) {
                $parent_name = $cls->superclass->name;
            } elsif ($cls->can('parent_name') && defined $cls->parent_name) {
                $parent_name = $cls->parent_name;
            }

            my $class_info = Chalk::IR::ClassInfo->new(
                name    => $name,
                parent  => $parent_name,
                fields  => [grep { $_ isa Chalk::IR::FieldInfo } @body],
                methods => [grep { $_ isa Chalk::IR::MethodInfo } @body],
                subs    => [grep { $_ isa Chalk::IR::SubInfo } @body],
                body    => \@body,
            );
            push @lines, $self->_emit_class_decl($class_info);
        }

        # Top-level subs registered on `main`
        if (defined $main) {
            for my $sub ($main->subs) {
                my $body_ref = $sub->body;
                my @sub_body = (ref($body_ref) eq 'ARRAY' && $body_ref->@*)
                    ? $body_ref->@*
                    : $self->_body_from_graph($sub->graph);
                my $sub_info = Chalk::IR::SubInfo->new(
                    name   => $sub->name,
                    params => $sub->params,
                    body   => \@sub_body,
                    graph  => $sub->graph,
                );
                my $line = $self->_emit_sub_decl($sub_info);
                push @lines, $line if defined $line;
            }
        }

        my $code = join("\n", @lines) . "\n";
        return { 'main.pm' => $code };
    }

    # Schedule-driven counterpart to _generate_from_mop. Walks the MOP
    # directly (no MethodInfo/ClassInfo synthesis); runs each method
    # body through Chalk::IR::Scheduler::EagerPinning to get a Schedule;
    # walks Schedule items with indent-tracked output, dispatching per
    # item kind. This is Phase 5a of the SoN scheduler migration; once
    # byte-identical with _generate_from_mop across the golden corpus,
    # generate($mop) switches to call this method instead.
    method _generate_from_schedule($mop) {
        my @lines;

        my $main = $mop->for_class('main');
        if (defined $main) {
            for my $import ($main->imports) {
                push @lines, $self->_emit_mop_import($import);
            }
        }

        for my $cls ($mop->classes()) {
            my $name = $cls->name;
            next if $name eq 'main';
            push @lines, $self->_emit_mop_class($cls);
        }

        if (defined $main) {
            for my $sub ($main->subs) {
                my $line = $self->_emit_mop_sub($sub, 'top_level');
                push @lines, $line if defined $line;
            }
        }

        my $code = join("\n", @lines) . "\n";
        return { 'main.pm' => $code };
    }

    # Emit a `use` declaration from a Chalk::MOP::Import.
    method _emit_mop_import($import) {
        my $module = $import->module;
        my @args   = $import->args;

        # Version strings don't get quoted (matches legacy _emit_use_decl).
        if ($module =~ /^v?[0-9]/) {
            if (@args) {
                my @arg_strs = map { $self->_emit_expr($_) } @args;
                return "use $module " . join(', ', @arg_strs) . ";";
            }
            return "use $module;";
        }

        if (@args) {
            my @arg_strs = map { $self->_emit_expr($_) } @args;
            return "use $module " . join(', ', @arg_strs) . ";";
        }

        return "use $module;";
    }

    # Emit a class declaration from a Chalk::MOP::Class. Walks fields
    # first, then methods, then subs (matching the legacy
    # _generate_from_mop synthesis order).
    method _emit_mop_class($cls) {
        my $name   = $cls->name;
        my $parent;
        if ($cls->can('superclass') && defined $cls->superclass) {
            $parent = $cls->superclass->name;
        } elsif ($cls->can('parent_name') && defined $cls->parent_name) {
            $parent = $cls->parent_name;
        }

        my $decl = "class $name";
        $decl .= " :isa($parent)" if defined $parent;
        $decl .= " {";

        my @body_lines;
        for my $field ($cls->fields) {
            push @body_lines, $self->_emit_mop_field($field);
        }
        for my $method ($cls->methods) {
            push @body_lines, $self->_emit_mop_method($method);
        }
        for my $sub ($cls->subs) {
            push @body_lines, $self->_emit_mop_sub($sub, 'class');
        }

        my @lines = ($decl);
        for my $b (@body_lines) {
            next unless defined $b;
            for my $line (split /\n/, $b) {
                push @lines, "    $line";
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit a field declaration from a Chalk::MOP::Field. MOP::Field
    # attributes are colon-prefixed strings (e.g. ':param', ':reader').
    method _emit_mop_field($field) {
        my $decl = "field " . $field->name;
        for my $attr ($field->attributes) {
            # Strip the leading ':' before emitting; _emit_field_decl
            # in the legacy path does the same munging.
            my $a = $attr =~ s/^://r;
            $decl .= " :$a";
        }
        if (defined $field->default_value) {
            $decl .= " = " . $self->_emit_expr($field->default_value);
        }
        return "$decl;";
    }

    # Emit a method declaration from a Chalk::MOP::Method, with body
    # produced by the EagerPinning scheduler.
    method _emit_mop_method($method) {
        my $name   = $method->name;
        my $params = $method->params;    # plain strings
        my $sig    = '(' . join(', ', $params->@*) . ')';

        # Scope aggregate vars: params shadow class-scope aggregate
        # names; method body may declare more.
        my %saved = %_aggregate_vars;
        $self->_scope_body_vars_mop($params, $method);
        my $body_code = $self->_emit_scheduled_body($method);
        %_aggregate_vars = %saved;

        return "method $name$sig {\n" . _indent_block($body_code) . "}";
    }

    # Emit a sub declaration from a Chalk::MOP::Sub. The $scope_kind
    # is 'class' (within a class declaration; emit as `sub`) or
    # 'top_level' (top-level sub; emit as `sub`). Currently both use
    # `sub`; the distinction exists in the MOP via a future
    # field-scope attribute and is preserved for symmetry with the
    # legacy _emit_sub_decl signature.
    method _emit_mop_sub($sub, $scope_kind = 'class') {
        my $name   = $sub->name;
        my $params = $sub->params;
        my $sig    = '(' . join(', ', $params->@*) . ')';

        my $prefix = 'sub';

        my %saved = %_aggregate_vars;
        $self->_scope_body_vars_mop($params, $sub);
        my $body_code = $self->_emit_scheduled_body($sub);
        %_aggregate_vars = %saved;

        return "$prefix $name$sig {\n" . _indent_block($body_code) . "}";
    }

    # Run the scheduler on a MOP method/sub and emit the resulting
    # Schedule as indented body lines. Returns the body as a single
    # string (without the enclosing `{` `}` — the caller wraps).
    method _emit_scheduled_body($method) {
        my $scheduler = Chalk::IR::Scheduler::EagerPinning->new;
        my $schedule  = $scheduler->schedule($method);

        my @lines;
        my $indent = 0;
        for my $item ($schedule->items->@*) {
            $self->_emit_schedule_item($item, \@lines, \$indent, $scheduler);
        }
        return join("\n", @lines);
    }

    # Emit a single Schedule Item into the lines accumulator. Pulled
    # out of _emit_scheduled_body so a synthetic Return whose value is
    # itself a control node (If/Loop/TryCatch) can recurse — the
    # scheduler's _expand_node turns that value into a sub-item-list
    # and we replay each through this helper.
    method _emit_schedule_item($item, $lines, $indent_ref, $scheduler) {
        my $kind = $item->kind;
        if ($kind eq 'stmt') {
            my $node = $item->node;
            my $code;
            # Synthetic Return: the parser inserted this for an
            # implicit fall-through (`{ EXPR }` with no explicit
            # return). Emit the bare value, no `return` keyword,
            # no trailing semicolon. Matches the legacy
            # _is_explicit_exit handling in _body_from_graph.
            if (blessed($node)
                    && $node isa Chalk::IR::Node::Return
                    && $node->can('synthetic')
                    && $node->synthetic)
            {
                my $val = $node->inputs->[1];
                if (defined $val
                        && blessed($val)
                        && ($val isa Chalk::IR::Node::If
                         || $val isa Chalk::IR::Node::Loop
                         || $val isa Chalk::IR::Node::TryCatch))
                {
                    # Synthetic Return whose value is a control
                    # node: the body's last expression IS the
                    # if/loop/try statement. Per Perl's last-
                    # expression-value semantics, the if/else
                    # itself is the trailing implicit-return form.
                    # Expand via the scheduler so the structured
                    # block_open/.../block_close sequence emits
                    # rather than dying in _emit_node (which
                    # doesn't accept If/Loop/TryCatch as expressions).
                    my @sub_items = $scheduler->_expand_node($val);
                    for my $sub_item (@sub_items) {
                        $self->_emit_schedule_item(
                            $sub_item, $lines, $indent_ref, $scheduler);
                    }
                    return;
                }
                if (defined $val) {
                    # _emit_node would add `return ` and `;`; the
                    # bare-value form still needs the trailing `;`.
                    $code = $self->_emit_node($val);
                } else {
                    $code = undef;
                }
            } else {
                $code = $self->_emit_node($node);
            }
            return unless defined $code;
            for my $l (split /\n/, $code) {
                push $lines->@*, ('    ' x $$indent_ref) . $l;
            }
        } elsif ($kind eq 'block_open') {
            my $head = $self->_emit_block_open_head($item);
            push $lines->@*, ('    ' x $$indent_ref) . $head;
            $$indent_ref++;
        } elsif ($kind eq 'block_close') {
            $$indent_ref-- if $$indent_ref > 0;
            push $lines->@*, ('    ' x $$indent_ref) . '}';
        } elsif ($kind eq 'else') {
            $$indent_ref-- if $$indent_ref > 0;
            push $lines->@*, ('    ' x $$indent_ref) . '} else {';
            $$indent_ref++;
        } elsif ($kind eq 'elsif') {
            $$indent_ref-- if $$indent_ref > 0;
            push $lines->@*, ('    ' x $$indent_ref)
                . '} ' . $self->_emit_elsif_head($item);
            $$indent_ref++;
        } elsif ($kind eq 'catch') {
            $$indent_ref-- if $$indent_ref > 0;
            push $lines->@*, ('    ' x $$indent_ref)
                . '} ' . $self->_emit_catch_head($item);
            $$indent_ref++;
        } else {
            die "Unknown Schedule Item kind: $kind";
        }
    }

    # Render the opening line for a block_open Item. $item->form selects
    # the surface syntax; the IR node carries the condition / iterator
    # / list / try info that the surface needs.
    method _emit_block_open_head($item) {
        my $form = $item->form // '';
        my $node = $item->node;

        if ($form eq 'if') {
            return $self->_emit_if_head($node);
        }
        if ($form eq 'while') {
            return $self->_emit_while_head($node);
        }
        if ($form eq 'foreach') {
            return $self->_emit_foreach_head($node);
        }
        if ($form eq 'for') {
            return $self->_emit_for_head($node);
        }
        if ($form eq 'try') {
            return 'try {';
        }
        die "Unknown block_open form: $form";
    }

    # `if (X) {` or `unless (X) {` — the latter when the condition is
    # a Not-wrapper around an inner expression (parser normalizes
    # `unless` to `if !cond` per Decision B). The codegen recovers
    # the source form.
    method _emit_if_head($if_node) {
        my $cond = $if_node->inputs->[1];
        my ($form_kw, $cond_expr) = $self->_recover_if_or_unless($cond);
        return "$form_kw ($cond_expr) {";
    }

    # `} elsif (X) {` head from an elsif-marker Item whose node is
    # the elsif's If.
    method _emit_elsif_head($item) {
        my $cond = $item->node->inputs->[1];
        my ($form_kw, $cond_expr) = $self->_recover_if_or_unless($cond);
        return "elsif ($cond_expr) {";
    }

    # Emit the if/unless condition. Currently always emits `if (!EXPR)`
    # for the negated form — matches the legacy codegen path exactly,
    # which is the Phase 5a byte-compat parity goal. Decision B's
    # codegen-side `unless` recovery target is a *future* switch we'd
    # turn on when regenerating goldens; the legacy goldens don't
    # exercise it. The signature returns (form_kw, expr) so callers
    # don't need to know which branch we took.
    method _recover_if_or_unless($cond) {
        return ('if', $self->_emit_expr($cond));
    }

    # `while (X) {` from a Loop node.
    method _emit_while_head($loop) {
        # The loop-condition is on the Loop's controlled If node's
        # inputs[1]. But Chalk::IR::Node::Loop doesn't expose the If
        # directly — we fish it from the body_proj's source.
        my $cond = $self->_loop_condition($loop);
        return "while ($cond) {";
    }

    # `for my $x (LIST) {` from a Loop node with iterator/list on
    # schedule_data.
    method _emit_foreach_head($loop) {
        my $sd = $loop->schedule_data;
        my $iter = $sd->iterator;
        my $list = $sd->list;
        my $iter_expr = $self->_emit_expr($iter);
        my $list_expr;
        if (ref($list) eq 'ARRAY') {
            $list_expr = join(', ', map { $self->_emit_expr($_) } $list->@*);
        } else {
            $list_expr = $self->_emit_expr($list);
        }
        return "for my $iter_expr ($list_expr) {";
    }

    # C-style for: `for (init; cond; step) {`. for_init and for_step
    # came off schedule_data; the loop condition is on the inner If.
    method _emit_for_head($loop) {
        my $sd = $loop->schedule_data;
        my $init_expr = defined $sd->for_init
            ? $self->_emit_expr_or_decl($sd->for_init) : '';
        my $cond_expr = $self->_loop_condition($loop);
        my $step_expr = defined $sd->for_step
            ? $self->_emit_expr_or_decl($sd->for_step) : '';
        return "for ($init_expr; $cond_expr; $step_expr) {";
    }

    # `} catch ($var) {` head from a catch-marker Item whose node is
    # the TryCatch.
    method _emit_catch_head($item) {
        my $try = $item->node;
        my $sd  = $try->schedule_data;
        my $var = $sd->catch_var;
        return "catch ($var) {";
    }

    # Walk a Loop's controlled If to extract its condition as Perl.
    method _loop_condition($loop) {
        # Find the If node controlled by this Loop. It's a consumer
        # of the Loop; iterate consumers and pick the first If.
        for my $c ($loop->consumers->@*) {
            return $self->_emit_expr($c->inputs->[1])
                if blessed($c) && $c isa Chalk::IR::Node::If;
        }
        return '';
    }

    # Emit a VarDecl as `my $x = ...` (no semicolon) for for-init
    # position. Plain expressions emit as themselves.
    method _emit_expr_or_decl($node) {
        if (blessed($node) && $node isa Chalk::IR::Node::VarDecl) {
            my $name = $node->name->value;
            my $init = $node->init;
            return defined $init
                ? "my $name = " . $self->_emit_expr($init)
                : "my $name";
        }
        return $self->_emit_expr($node);
    }

    # Scope aggregate vars from a MOP method/sub's params + lexical
    # bindings. The legacy _scope_body_vars walks a body arrayref;
    # the MOP-driven path uses the method's lexical bindings list.
    method _scope_body_vars_mop($params, $method) {
        for my $p ($params->@*) {
            my $pname = $p;
            if ($pname =~ /^\$(.+)/) {
                delete $_aggregate_vars{$1};
            }
        }
        # Walk the method's graph to find VarDecls (same approach the
        # legacy synthesis uses, just driven by MOP graph instead of
        # the synthesized body arrayref).
        my $graph = $method->graph;
        return unless defined $graph;
        for my $n ($graph->nodes->@*) {
            next unless $n isa Chalk::IR::Node::VarDecl;
            my $var = $n->name;
            next unless defined $var && $var isa Chalk::IR::Node::Constant;
            my $vname = $var->value;
            if (defined $vname && $vname =~ /^([\@\%])(.+)/) {
                $_aggregate_vars{$2} = $1;
            }
        }
    }

    # Helper: indent a multi-line code block by 4 spaces.
    sub _indent_block($code) {
        return '' unless defined $code && length $code;
        my @lines = split /\n/, $code;
        my @out;
        for my $l (@lines) {
            push @out, length($l) ? "    $l" : $l;
        }
        return join("\n", @out) . "\n";
    }

    # Recover ordered body statements from a method/sub graph for the
    # legacy _emit_method_decl / _emit_sub_decl helpers, which still
    # walk a body arrayref. Body statements are the side-effect nodes
    # in the control chain (VarDecl, Assign, Call, etc.) plus the
    # Return at the tail.
    #
    # Walks the chain from Return.inputs[0] backward through side-effect
    # node controls, then reverses to source order. Returns ([] on
    # absent/empty graph).
    method _body_from_graph($graph) {
        return () unless defined $graph;
        my @returns = $graph->returns->@*;
        return () unless @returns;
        my $exit = $returns[0];

        # Walk backward via inputs[0] (control), collecting non-Start
        # nodes until we hit Start.
        my @reverse;
        my $cur = $exit->inputs->[0];
        while (defined $cur && blessed($cur)) {
            last if $cur->operation eq 'Start';
            push @reverse, $cur;
            my $ins = $cur->inputs;
            last unless defined $ins && ref($ins) eq 'ARRAY';
            $cur = $ins->[0];
        }

        my @body = reverse @reverse;

        # The exit itself: include the Return / Unwind so the emitter
        # can render `return EXPR;` / `die EXPR;` as in source. For
        # implicit-return cases (the parser synthesized this Return),
        # the user wrote `EXPR` as a bare trailing statement - emit
        # the bare value, not a synthesized `return EXPR;`.
        if (_is_explicit_exit($exit)) {
            push @body, $exit;
        } else {
            my $val = $exit->inputs->[1];
            if (defined $val && blessed($val)) {
                my $tail = $body[-1];
                unless (defined $tail && blessed($tail)
                        && refaddr($tail) == refaddr($val)) {
                    push @body, $val;
                }
            }
        }
        return @body;
    }

    # Exit classification: a Return is "synthetic" when the parser
    # built it for the implicit-fall-through case (bare trailing
    # expression). Marker carried on Chalk::IR::Node::Return.synthetic.
    # Unwind is always explicit (`die EXPR`).
    sub _is_explicit_exit($exit) {
        return false unless defined $exit && blessed($exit);
        return true if $exit isa Chalk::IR::Node::Unwind;
        return false unless $exit isa Chalk::IR::Node::Return;
        return !($exit->can('synthetic') && $exit->synthetic);
    }

    # Generate code with cfg_state-aware dispatch for control flow.
    # Walks the Context tree to build IR node → cfg_state lookup,
    # then generates code using cfg_state for if/loop dispatch.
    method _generate_with_cfg($ir, $sa, $ctx) {
        die "_generate_with_cfg() requires a Program IR node"
            unless defined($ir) && $ir isa Chalk::IR::Program;

        %_cfg_lookup = ();
        %_aggregate_vars = ();
        $self->_build_cfg_lookup($sa, $ctx);
        $self->_scan_aggregate_vars($ir);
        my $code = $self->_emit_program($ir);
        %_cfg_lookup = ();
        %_aggregate_vars = ();
        return $code;
    }

    # Walk Context tree, mapping IR node refaddr → cfg_state for control flow nodes.
    # First-found wins: parent rules (e.g. ExpressionStatement) that wire body
    # expressions into cfg_state take priority over child rules (e.g. PostfixModifier)
    # that have empty stmts.
    method _build_cfg_lookup($sa, $ctx) {
        my @stack = ($ctx);
        while (@stack) {
            my $node = pop @stack;
            my $state = $node->cfg_state();
            if (defined $state && (defined $state->{if_node} || defined $state->{loop} || defined $state->{try_node})) {
                my $ir_node = $node->extract();
                # Only register IR nodes that are directly associated with
                # control flow — not parent nodes (ClassDecl, MethodDecl,
                # Program) that inherit cfg_state from child If/Loop nodes.
                # cfg_state propagates upward through the Context comonad,
                # so without this guard, ClassDecl gets mapped to an If and
                # _emit_node emits a bare if-block instead of the class.
                if (defined $ir_node && ref($ir_node) && !exists $_cfg_lookup{refaddr($ir_node)}
                        && !($ir_node isa Chalk::IR::Program)
                        && !($ir_node isa Chalk::IR::UseInfo)
                        && !($ir_node isa Chalk::IR::ClassInfo)
                        && !($ir_node isa Chalk::IR::FieldInfo)
                        && !($ir_node isa Chalk::IR::MethodInfo)
                        && !($ir_node isa Chalk::IR::SubInfo)) {
                    $_cfg_lookup{refaddr($ir_node)} = $state;
                }
            }
            push @stack, reverse $node->children()->@*;
        }
        return;
    }

    # Scan IR tree for VarDecl nodes with aggregate sigils (% or @).
    # Populates %_aggregate_vars so _emit_subscript_expr can emit
    # $hash{key} instead of $hash->{key} for hash variables.
    method _scan_aggregate_vars($ir) {
        my @stack = ($ir);
        while (@stack) {
            my $node = pop @stack;
            next unless defined $node && ref($node);
            if ($node isa Chalk::IR::Node::VarDecl) {
                my $var = $node->name();
                if (defined $var && $var isa Chalk::IR::Node::Constant) {
                    my $name = $var->value();
                    if (defined $name && $name =~ /^([\@\%])(.+)/) {
                        $_aggregate_vars{$2} = $1;
                    }
                }
            }
            if ($node isa Chalk::IR::Program) {
                # Program metadata struct — push all contained items for traversal
                push @stack, $node->use_decls()->@*;
                push @stack, $node->classes()->@*;
                push @stack, $node->top_level_subs()->@*;
                push @stack, $node->other_stmts()->@*;
            } elsif ($node isa Chalk::IR::ClassInfo) {
                # ClassInfo metadata struct — push body items for traversal
                push @stack, $node->body()->@*;
            } elsif ($node isa Chalk::IR::FieldInfo) {
                # FieldInfo metadata struct — check for aggregate-sigil field names
                my $name = $node->name();
                if (defined $name && $name =~ /^([\@\%])(.+)/) {
                    $_aggregate_vars{$2} = $1;
                }
            } elsif (ref($node) && ref($node) ne 'HASH' && $node->can('inputs')) {
                for my $input ($node->inputs()->@*) {
                    if (ref($input) eq 'ARRAY') {
                        push @stack, grep { ref($_) ne 'HASH' } @$input;
                    } elsif (ref($input) && ref($input) ne 'HASH') {
                        push @stack, $input;
                    }
                }
            }
        }
    }

    method generate_distribution($ir) {
        # For Perl target, return a single file mapping
        my $code = $self->generate($ir);

        # Extract class name from the IR to determine file path
        my $class_name;
        for my $stmt ($ir->classes()->@*, $ir->top_level_subs()->@*) {
            if ($stmt isa Chalk::IR::ClassInfo) {
                $class_name = $stmt->name();
                last;
            }
        }

        if (defined $class_name) {
            my $path = $class_name;
            $path =~ s{::}{/}g;
            return { "lib/$path.pm" => $code };
        }

        return { 'output.pm' => $code };
    }

    method _emit_program($node) {
        my @stmts;
        # Reassemble ordered output: use_decls first, then classes, top-level subs, other
        push @stmts, $node->use_decls()->@*;
        push @stmts, $node->classes()->@*;
        push @stmts, $node->top_level_subs()->@*;
        push @stmts, $node->other_stmts()->@*;
        my @lines;
        for my $stmt (@stmts) {
            my $line = $self->_emit_node($stmt);
            push @lines, $line if defined $line;
        }
        return join("\n", @lines) . "\n";
    }

    method _emit_node($node) {
        return undef unless defined $node;

        # Check cfg_state lookup for control flow dispatch
        if (%_cfg_lookup && ref($node)) {
            my $state = $_cfg_lookup{refaddr($node)};
            if (defined $state) {
                if (defined $state->{if_node}) {
                    # loop_jump: emit 'next if/unless $cond' instead of block
                    if (defined $state->{loop_jump}) {
                        return $self->_emit_loop_jump(
                            $state->{loop_jump},
                            $state->{if_node},
                        );
                    }
                    return $self->emit_cfg_if(
                        $state->{if_node},
                        $state->{true_proj},
                        $state->{false_proj},
                        $state->{then_stmts} // [],
                        $state->{else_stmts} // [],
                    );
                }
                if (defined $state->{loop}) {
                    return $self->emit_cfg_loop(
                        $state->{loop},
                        $state->{loop_if},
                        $state->{body_proj},
                        $state->{exit_proj},
                        $state->{body_stmts} // [],
                        $state->{iterator},
                        $state->{list},
                    );
                }
                if (defined $state->{try_node}) {
                    return $self->emit_cfg_try_catch(
                        $state->{try_stmts}   // [],
                        $state->{catch_var},
                        $state->{catch_stmts} // [],
                    );
                }
            }
        }

        if ($node isa Chalk::IR::Node::Constant) {
            # Loop control keywords must be emitted as bare keywords, not quoted
            my $val = $node->value() // '';
            if ($val eq 'next' || $val eq 'last' || $val eq 'redo') {
                return "$val;";
            }
            return $self->_emit_constant($node);
        }

        # Typed fast-paths for computation nodes (expression-as-statement)
        if ($node isa Chalk::IR::Node::BinOp
                || $node isa Chalk::IR::Node::UnaryOp
                || $node isa Chalk::IR::Node::Call
                || $node isa Chalk::IR::Node::Subscript
                || $node isa Chalk::IR::Node::PostfixDeref
                || $node isa Chalk::IR::Node::HashRef
                || $node isa Chalk::IR::Node::ArrayRef
                || $node isa Chalk::IR::Node::AnonSub
                || $node isa Chalk::IR::Node::RegexMatch
                || $node isa Chalk::IR::Node::RegexSubst
                || $node isa Chalk::IR::Node::BacktickExpr
                || $node isa Chalk::IR::Node::Interpolate
                || $node isa Chalk::IR::Node::TernaryExpr
                || $node isa Chalk::IR::Node::StructRef
                || $node isa Chalk::IR::Node::StructFieldAccess) {
            return $self->_emit_expr($node) . ";";
        }
        if ($node isa Chalk::IR::Node::VarDecl) {
            return $self->_emit_var_decl($node);
        }
        if ($node isa Chalk::IR::Node::CompoundAssign) {
            return $self->_emit_compound_assign($node) . ";";
        }

        if ($node isa Chalk::IR::UseInfo) {
            return $self->_emit_use_decl($node);
        }

        if ($node isa Chalk::IR::FieldInfo) {
            return $self->_emit_field_decl($node);
        }

        if ($node isa Chalk::IR::MethodInfo) {
            return $self->_emit_method_decl($node);
        }

        if ($node isa Chalk::IR::SubInfo) {
            return $self->_emit_sub_decl($node);
        }

        if ($node isa Chalk::IR::ClassInfo) {
            return $self->_emit_class_decl($node);
        }

        if ($node isa Chalk::IR::Node::Return) { return $self->_emit_return_stmt($node); }
        if ($node isa Chalk::IR::Node::Unwind) { return $self->_emit_die_call($node); }
        if ($node isa Chalk::IR::Node::TryCatch) { return $self->_emit_expr($node) . ";"; }
        if ($node isa Chalk::IR::Node::ExpressionList) {
            # ExpressionList in statement position — emit as a parenthesized
            # list expression. Used by ($a, $b, $c) tuple expressions at the
            # statement level (rare; usually wraps as a Call argument).
            my @items = $node->items->@*;
            return '(' . join(', ', map { $self->_emit_expr($_) } @items) . ');';
        }

        # Every IR node type must have an explicit handler above. If we reach
        # here, a new node type was added without a corresponding emitter —
        # that's a bug, not a missing feature. Don't add a catch-all.
        die "Unknown IR node type: " . ref($node);
    }

    method _emit_constant($node) {
        my $value = $node->value();
        return "'" . $self->_escape_single_quote($value) . "'";
    }

    method _emit_use_decl($node) {
        my $kw          = $node->keyword();
        my $module_name = $node->name();
        my $args = scalar($node->args()->@*) ? $node->args() : undef;

        # Version strings don't get quoted
        if ($module_name =~ /^v?[0-9]/) {
            if (defined $args) {
                my @arg_strs = map { $self->_emit_expr($_) } $args->@*;
                return "$kw $module_name " . join(', ', @arg_strs) . ";";
            }
            return "$kw $module_name;";
        }

        if (defined $args) {
            my @arg_strs = map { $self->_emit_expr($_) } $args->@*;
            return "$kw $module_name " . join(', ', @arg_strs) . ";";
        }

        return "$kw $module_name;";
    }

    method _emit_class_decl($node) {
        my $name   = $node->name();
        my $parent = $node->parent();
        my $body   = $node->body();

        my $decl = "class $name";
        if (defined $parent) {
            $decl .= " :isa($parent)";
        }
        $decl .= " {";

        my @lines = ($decl);
        for my $item ($body->@*) {
            my $code = $self->_emit_node($item);
            if (defined $code) {
                # Indent body by 4 spaces
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";

        return join("\n", @lines);
    }

    method _emit_method_decl($node) {
        my $name   = $node->name();
        my $params = $node->params();    # plain strings
        my $body   = $node->body();

        # Merge per-method graph schedule into cfg_lookup (additive).
        # The global cfg_lookup (built from the Context tree) is already
        # populated; the graph schedule supplements it for nodes that may
        # have been missed due to filter-gap merges in the parser (see
        # _fix_postfix_chain in Perl/Actions.pm for the canonical
        # filter-gap-merge explanation).
        if (defined $node->graph()) {
            my $sched = $node->graph()->schedule();
            for my $key (keys $sched->%*) {
                $_cfg_lookup{$key} //= $sched->{$key};
            }
        }

        my $sig = '(' . join(', ', $params->@*) . ')';
        # Scope aggregate vars: params shadow class-scope aggregate names
        my %saved = %_aggregate_vars;
        $self->_scope_body_vars($params, $body);
        my $result = $self->_emit_body_block("method $name$sig {", $body);
        %_aggregate_vars = %saved;
        return $result;
    }

    method _emit_sub_decl($node) {
        my $name   = $node->name();
        my $params = $node->params();    # plain strings
        my $body   = $node->body();
        my $scope  = $node->scope();

        # Merge per-sub graph schedule into cfg_lookup (additive).
        if (defined $node->graph()) {
            my $sched = $node->graph()->schedule();
            for my $key (keys $sched->%*) {
                $_cfg_lookup{$key} //= $sched->{$key};
            }
        }

        my $sig = '(' . join(', ', $params->@*) . ')';
        my $prefix = $scope eq 'package' ? 'sub' : "$scope sub";
        # Scope aggregate vars: params shadow class-scope aggregate names
        my %saved = %_aggregate_vars;
        $self->_scope_body_vars($params, $body);
        my $result = $self->_emit_body_block("$prefix $name$sig {", $body);
        %_aggregate_vars = %saved;
        return $result;
    }

    # Adjust %_aggregate_vars for a method/sub body scope.
    # Remove param names (params are always scalars) and add body-local
    # VarDecl aggregate names.
    # $params: plain strings from MethodInfo/SubInfo.
    method _scope_body_vars($params, $body) {
        # Params shadow: $reachable param means $reachable is a scalar here
        for my $p ($params->@*) {
            my $pname = $p;
            if ($pname =~ /^\$(.+)/) {
                delete $_aggregate_vars{$1};
            }
        }
        # Add body-local aggregate VarDecls
        for my $item ($body->@*) {
            next unless $item isa Chalk::IR::Node::VarDecl;
            my $var = $item->name();
            next unless defined $var && $var isa Chalk::IR::Node::Constant;
            my $vname = $var->value();
            if (defined $vname && $vname =~ /^([\@\%])(.+)/) {
                $_aggregate_vars{$2} = $1;
            }
        }
    }

    method _emit_body_block($decl_line, $body) {
        my @lines = ($decl_line);
        for my $item ($body->@*) {
            my $code = $self->_emit_node($item);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }

    method _emit_return_stmt($node) {
        my $value = $node->inputs()->[1];  # inputs[0]=control, inputs[1]=value
        return "return " . $self->_emit_expr($value) . ";";
    }

    method _emit_die_call($node) {
        my $args = $node->inputs()->[1];
        my @arg_strs = map { $self->_emit_expr($_) } $args->@*;
        return "die " . join(', ', @arg_strs) . ";";
    }

    method _emit_field_decl($node) {
        my $name          = $node->name();
        my $attrs         = $node->attributes();
        my $default_value = $node->default_value();
        my $decl = "field $name";

        if (ref($attrs) eq 'ARRAY' && $attrs->@*) {
            for my $attr ($attrs->@*) {
                my $attr_name;
                if (ref($attr) eq 'HASH') {
                    $attr_name = $attr->{name};
                } else {
                    # Legacy Constructor:_Attribute node
                    $attr_name = $attr->inputs()->[0]->value();
                }
                $decl .= " :$attr_name";
            }
        }

        if (defined $default_value) {
            $decl .= " = " . $self->_emit_expr($default_value);
        }

        return "$decl;";
    }

    method _emit_interpolated_string($node) {
        my $parts = $node->inputs()->[0];
        my $result = '"';
        for my $part ($parts->@*) {
            if ($part->const_type() eq 'variable') {
                $result .= $part->value();
            } else {
                # Literal string — escape for double-quoted context
                my $lit = $part->value();
                $lit =~ s/\\/\\\\/g;
                $lit =~ s/"/\\"/g;
                $lit =~ s/\n/\\n/g;
                $lit =~ s/\t/\\t/g;
                $lit =~ s/\$/\\\$/g;
                $lit =~ s/\@/\\\@/g;
                $result .= $lit;
            }
        }
        $result .= '"';
        return $result;
    }

    # Emit an expression (no trailing semicolon, no statement wrapper)
    method _emit_expr($node) {
        return 'undef' unless defined $node;

        if ($node isa Chalk::IR::Node::Constant) {
            my $val = $node->value();
            my $ct = $node->const_type();
            # Variables and special values don't get quoted
            if ($ct eq 'variable' || $val =~ /^[\$\@\%]/) {
                return $val;
            }
            # Numeric values
            if ($val =~ /^-?[0-9]+(?:\.[0-9]+)?$/) {
                return $val;
            }
            # Boolean/special values
            if ($val eq 'true' || $val eq 'false' || $val eq 'undef') {
                return $val;
            }
            # Regex literals — emit bare (not quoted)
            if ($ct eq 'regex') {
                return $val;
            }
            return "'" . $self->_escape_single_quote($val) . "'";
        }

        # Typed fast-paths for computation nodes
        if ($node isa Chalk::IR::Node::Interpolate) { return $self->_emit_interpolated_string($node); }
        if ($node isa Chalk::IR::Node::BinOp)       { return $self->_emit_binary_expr($node); }
        if ($node isa Chalk::IR::Node::UnaryOp)     { return $self->_emit_unary_expr($node); }
        if ($node isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'method') {
            return $self->_emit_method_call_expr($node);
        }
        if ($node isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'builtin') {
            return $self->_emit_builtin_call($node);
        }
        if ($node isa Chalk::IR::Node::Subscript)   { return $self->_emit_subscript_expr($node); }
        if ($node isa Chalk::IR::Node::PostfixDeref) { return $self->_emit_postfix_deref_expr($node); }
        if ($node isa Chalk::IR::Node::HashRef)     { return $self->_emit_hash_ref_expr($node); }
        if ($node isa Chalk::IR::Node::ArrayRef)    { return $self->_emit_array_ref_expr($node); }
        if ($node isa Chalk::IR::Node::AnonSub)     { return $self->_emit_anon_sub_expr($node); }
        if ($node isa Chalk::IR::Node::RegexMatch)  { return $self->_emit_regex_match($node); }
        if ($node isa Chalk::IR::Node::RegexSubst)  { return $self->_emit_regex_subst($node); }
        if ($node isa Chalk::IR::Node::BacktickExpr) { return $self->_emit_backtick_expr($node); }
        if ($node isa Chalk::IR::Node::CompoundAssign) { return $self->_emit_compound_assign($node); }
        if ($node isa Chalk::IR::Node::VarDecl)     { return $self->_emit_var_decl_expr($node); }
        if ($node isa Chalk::IR::Node::TernaryExpr)       { return $self->_emit_ternary_expr($node); }
        if ($node isa Chalk::IR::Node::StructRef)         { return $self->_emit_struct_ref_expr($node); }
        if ($node isa Chalk::IR::Node::StructFieldAccess) { return $self->_emit_field_access_expr($node); }

        return $self->_emit_node($node);
    }

    method _emit_var_decl($node) {
        my $var  = $node->name()->value();
        my $init = $node->init();

        if (defined $init) {
            return "my $var = " . $self->_emit_init_expr($var, $init) . ";";
        }
        return "my $var;";
    }

    # VarDecl as expression (no semicolon)
    method _emit_var_decl_expr($node) {
        my $var  = $node->name()->value();
        my $init = $node->init();

        if (defined $init) {
            return "my $var = " . $self->_emit_init_expr($var, $init);
        }
        return "my $var";
    }

    # Emit a VarDecl initializer expression.
    # For %hash or @array variables initialized with a HashRef/ArrayRef node,
    # emit as a parenthesized list rather than a ref constructor.
    method _emit_init_expr($var, $init) {
        # Hash variable with HashRefExpr init: emit as (k, v, ...) not { k, v, ... }
        if ($var =~ /^\%/ && $init isa Chalk::IR::Node::HashRef) {
            my $pairs = $init->inputs()->[0];
            if ($pairs->@*) {
                my @strs = map { $self->_emit_expr($_) } $pairs->@*;
                return '(' . join(', ', @strs) . ')';
            }
            return '()';
        }
        # Array variable with ArrayRef init: emit as (elems) not [elems]
        if ($var =~ /^\@/ && $init isa Chalk::IR::Node::ArrayRef) {
            my $elems = $init->inputs()->[0];
            if ($elems->@*) {
                my @strs = map { $self->_emit_expr($_) } $elems->@*;
                return '(' . join(', ', @strs) . ')';
            }
            return '()';
        }
        return $self->_emit_expr($init);
    }

    method _emit_binary_expr($node) {
        my $op    = $node->inputs()->[0]->value();
        my $left  = $node->inputs()->[1];
        my $right = $node->inputs()->[2];

        return $self->_emit_expr($left) . " $op " . $self->_emit_expr($right);
    }

    method _emit_unary_expr($node) {
        my $op      = $node->inputs()->[0]->value();
        my $operand = $node->inputs()->[1];

        # Parenthesize compound operands to preserve precedence
        # (e.g., unless desugars to !cond, and !$a && $b != !($a && $b))
        my $needs_parens = ($operand isa Chalk::IR::Node::BinOp)
            || ($operand isa Chalk::IR::Node::TernaryExpr);

        my $expr = $self->_emit_expr($operand);
        if ($needs_parens) {
            $expr = "($expr)";
        }

        if ($op eq 'not') {
            return "not $expr";
        }
        return "$op$expr";
    }

    method _emit_compound_assign($node) {
        my $op     = $node->inputs()->[0]->value();
        my $target = $node->inputs()->[1];
        my $value  = $node->inputs()->[2];

        return $self->_emit_expr($target) . " $op " . $self->_emit_expr($value);
    }

    method _emit_method_call_expr($node) {
        my $invocant    = $node->inputs()->[0];
        my $method_name = $node->inputs()->[1]->value();
        my $args        = $node->inputs()->[2];

        my $inv = defined $invocant ? $self->_emit_expr($invocant) : '$self';
        my @arg_strs = map { $self->_emit_expr($_) } $args->@*;
        return "$inv->$method_name(" . join(', ', @arg_strs) . ")";
    }

    # Prefix builtins that take a single argument and should absorb subscripts:
    # exists $hash{key}, delete $arr[0], defined $h{k}, etc.
    my %SUBSCRIPT_ABSORBING_BUILTINS = map { $_ => 1 }
        qw(exists delete defined scalar ref);

    method _emit_subscript_expr($node) {
        my $target = $node->inputs()->[0];
        my $index  = $node->inputs()->[1];
        my $style  = $node->inputs()->[2]->value();

        # Filter-gap merge artifact: SubscriptExpr(BuiltinCall(exists, [$var]), $key)
        # should emit as exists($var->{$key}), not exists($var)->{$key}.
        # Push the subscript inside the builtin argument. (Precedence-inversion
        # gap class — see _fix_postfix_chain in Perl/Actions.pm.)
        if (defined $target
                && ($target isa Chalk::IR::Node::Call && $target->dispatch_kind() eq 'builtin')) {
            my $bname = $target->inputs()->[0]->value();
            if ($SUBSCRIPT_ABSORBING_BUILTINS{$bname}) {
                my @args = $target->inputs()->[1]->@*;
                my $inner = $args[-1];
                my $inner_expr = $self->_emit_expr($inner);
                my $sub_expr = $self->_format_subscript($inner_expr, $index, $style);
                my @other_args = map { $self->_emit_expr($_) } @args[0 .. $#args - 1];
                return "$bname(" . join(', ', @other_args, $sub_expr) . ")";
            }
        }

        # Filter-gap merge artifact: SubscriptExpr(UnaryExpr(!, BuiltinCall(exists, ...)), $key)
        # Push the subscript past the unary op into the builtin argument.
        if (defined $target
                && ($target isa Chalk::IR::Node::UnaryOp)) {
            my $op = $target->inputs()->[0]->value();
            my $operand = $target->inputs()->[1];
            if ($operand isa Chalk::IR::Node::Call && $operand->dispatch_kind() eq 'builtin') {
                my $bname = $operand->inputs()->[0]->value();
                if ($SUBSCRIPT_ABSORBING_BUILTINS{$bname}) {
                    my @args = $operand->inputs()->[1]->@*;
                    my $inner = $args[-1];
                    my $inner_expr = $self->_emit_expr($inner);
                    my $sub_expr = $self->_format_subscript($inner_expr, $index, $style);
                    my @other_args = map { $self->_emit_expr($_) } @args[0 .. $#args - 1];
                    return "$op$bname(" . join(', ', @other_args, $sub_expr) . ")";
                }
            }
        }

        my $tgt = defined $target ? $self->_emit_expr($target) : '$self';

        # Direct hash/array element: if the target is a $ variable whose name
        # was declared with % or @ sigil, emit direct subscript (no arrow).
        # $hash{key} for %hash, $arr[idx] for @array.
        if ($tgt =~ /^\$(.+)/ && %_aggregate_vars && exists $_aggregate_vars{$1}) {
            if ($style eq 'array') {
                return "$tgt\[" . $self->_emit_expr($index) . "]";
            }
            if ($style ne 'call') {
                return "$tgt\{" . $self->_emit_expr($index) . "}";
            }
        }

        if ($style eq 'array') {
            return "$tgt\->[" . $self->_emit_expr($index) . "]";
        }
        if ($style eq 'call') {
            # Coderef call: $f->($arg1, $arg2)
            my @args;
            if (ref($index) eq 'ARRAY') {
                @args = map { $self->_emit_expr($_) } $index->@*;
            } elsif (defined $index) {
                @args = ($self->_emit_expr($index));
            }
            return "$tgt\->(" . join(', ', @args) . ")";
        }
        return "$tgt\->{" . $self->_emit_expr($index) . "}";
    }

    # Format a subscript access, using direct syntax for aggregate vars.
    method _format_subscript($tgt_expr, $index_node, $style) {
        my $idx = $self->_emit_expr($index_node);
        my $is_aggregate = ($tgt_expr =~ /^\$(.+)/ && %_aggregate_vars
                            && exists $_aggregate_vars{$1});
        if ($style eq 'array') {
            return $is_aggregate ? "${tgt_expr}[$idx]" : "${tgt_expr}->[$idx]";
        }
        return $is_aggregate ? "${tgt_expr}\{$idx}" : "${tgt_expr}->{$idx}";
    }

    method _emit_postfix_deref_expr($node) {
        my $target = $node->inputs()->[0];
        my $sigil  = $node->inputs()->[1]->value();

        my $tgt = defined $target ? $self->_emit_expr($target) : '$self';
        return "$tgt\->${sigil}*";
    }

    method _emit_ternary_expr($node) {
        my $cond       = $node->inputs()->[0];
        my $true_expr  = $node->inputs()->[1];
        my $false_expr = $node->inputs()->[2];

        return $self->_emit_expr($cond) . " ? "
             . $self->_emit_expr($true_expr) . " : "
             . $self->_emit_expr($false_expr);
    }

    method _emit_hash_ref_expr($node) {
        my $pairs = $node->inputs()->[0];
        if (!$pairs->@*) {
            return '{}';
        }
        my @strs = map { $self->_emit_expr($_) } $pairs->@*;
        return '{ ' . join(', ', @strs) . ' }';
    }

    # Lower StructRef back to hash constructor: { key1 => val1, key2 => val2, ... }
    method _emit_struct_ref_expr($node) {
        my $schema_name = $node->inputs()->[0]->value();
        my $field_vals  = $node->inputs()->[1];

        my $schema = $_struct_schemas->{$schema_name};
        unless (defined $schema) {
            # Fallback: emit as empty hash if schema not found
            return '{}';
        }

        my @fields = $schema->{fields}->@*;
        my @pairs;
        for my $i (0 .. $#fields) {
            my $key = "'" . $fields[$i]{name} . "'";
            my $val = (defined $field_vals && $i < scalar($field_vals->@*))
                ? $self->_emit_expr($field_vals->[$i])
                : 'undef';
            push @pairs, "$key => $val";
        }

        return '{ ' . join(', ', @pairs) . ' }';
    }

    # Lower FieldAccess back to hash key access: $target->{'field_name'}
    method _emit_field_access_expr($node) {
        my $target     = $node->inputs()->[2];
        my $field_name = $node->inputs()->[1]->value();

        my $tgt = defined $target ? $self->_emit_expr($target) : '$self';
        return "$tgt\->{'$field_name'}";
    }

    method _emit_array_ref_expr($node) {
        my $elements = $node->inputs()->[0];
        if (!$elements->@*) {
            return '[]';
        }
        my @strs = map { $self->_emit_expr($_) } $elements->@*;
        return '[' . join(', ', @strs) . ']';
    }

    method _emit_anon_sub_expr($node) {
        my $params = $node->inputs()->[0];
        my $body   = $node->inputs()->[1];

        my $sig = '(' . join(', ', map { $_->value() } $params->@*) . ')';
        my @lines = ("sub $sig {");
        for my $stmt ($body->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }

    method _emit_regex_match($node) {
        my $target  = $node->inputs()->[0];
        my $pattern = $node->inputs()->[1];

        my $pat_val = $pattern->value();
        return $self->_emit_expr($target) . " =~ $pat_val";
    }

    method _emit_regex_subst($node) {
        my $target      = $node->inputs()->[0];
        my $pattern     = $node->inputs()->[1]->value();
        my $replacement = $node->inputs()->[2]->value();
        my $flags       = $node->inputs()->[3]->value();

        return $self->_emit_expr($target) . " =~ s/$pattern/$replacement/$flags";
    }

    method _emit_builtin_call($node) {
        my $name = $node->inputs()->[0]->value();
        my $args = $node->inputs()->[1];

        # Block-argument form: map { BLOCK } LIST, grep { BLOCK } LIST, sort { BLOCK } LIST
        # First arg is AnonSubExpr representing the block.
        if ($args->@* >= 1 && $args->[0] isa Chalk::IR::Node::AnonSub) {
            my $block_node = $args->[0];
            my $body = $block_node->inputs()->[1];  # body is inputs[1]
            my @body_items = ref($body) eq 'ARRAY' ? $body->@* : ($body);
            my @body_strs = map { $self->_emit_node($_) } @body_items;
            my $block_str = '{ ' . join(' ', @body_strs) . ' }';

            my @rest = $args->@[1 .. $#{$args}];
            if (@rest) {
                my @rest_strs = map { $self->_emit_expr($_) } @rest;
                return "$name $block_str " . join(', ', @rest_strs);
            }
            return "$name $block_str";
        }

        my @arg_strs = map { $self->_emit_expr($_) } $args->@*;

        # Some builtins use list syntax (no parens)
        if ($name eq 'push' || $name eq 'unshift' || $name eq 'die'
                || $name eq 'return' || $name eq 'print' || $name eq 'say') {
            return "$name " . join(', ', @arg_strs);
        }

        return "$name(" . join(', ', @arg_strs) . ")";
    }

    # Emit 'next if/unless $cond' from an If CFG node with loop_jump marker.
    # PostfixModifier negated the condition for 'unless', so the If node's
    # condition is !($original). We detect the negation wrapper and strip it
    # to emit 'next unless $original' for readability.
    # The If node is found via _build_cfg_lookup (cfg_state side-table keyed
    # by IR node refaddr). GCM/DCE passes that need to see this conditional
    # branch must walk cfg_state, not just the IR statement list.
    method _emit_loop_jump($jump_keyword, $if_node) {
        my $cond = $if_node->inputs()->[1];
        # Detect negation wrapper: UnaryExpr('!', expr) → emit 'unless expr'
        if (($cond isa Chalk::IR::Node::UnaryOp)
                && $cond->inputs()->[0] isa Chalk::IR::Node::Constant
                && $cond->inputs()->[0]->value() eq '!') {
            my $inner = $cond->inputs()->[1];
            return "$jump_keyword unless " . $self->_emit_expr($inner) . ";";
        }
        return "$jump_keyword if " . $self->_emit_expr($cond) . ";";
    }

    # Emit Perl if/else from an If CFG node with true/false Proj branches.
    # $true_proj/$false_proj: retained for future GCM/peephole passes
    # that schedule data-flow nodes relative to Proj control anchors.
    method emit_cfg_if($if_node, $true_proj, $false_proj,
                       $true_stmts = [], $false_stmts = [],
                       $prefix = 'if') {
        my $cond = $if_node->inputs()->[1];  # condition input
        my $cond_expr = $self->_emit_expr($cond);

        my @lines;
        push @lines, "$prefix ($cond_expr) {";
        for my $stmt ($true_stmts->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        if ($false_stmts->@*) {
            # Detect elsif: single If CFG node in else branch
            if (scalar $false_stmts->@* == 1
                    && ref($false_stmts->[0])
                    && %_cfg_lookup) {
                my $elsif_state = $_cfg_lookup{refaddr($false_stmts->[0])};
                if (defined $elsif_state && defined $elsif_state->{if_node}) {
                    my $elsif_code = $self->emit_cfg_if(
                        $elsif_state->{if_node},
                        $elsif_state->{true_proj},
                        $elsif_state->{false_proj},
                        $elsif_state->{then_stmts} // [],
                        $elsif_state->{else_stmts} // [],
                        '} elsif',
                    );
                    push @lines, $elsif_code;
                    return join("\n", @lines);
                }
            }
            push @lines, "} else {";
            for my $stmt ($false_stmts->@*) {
                my $code = $self->_emit_node($stmt);
                if (defined $code) {
                    for my $line (split /\n/, $code) {
                        push @lines, "    $line";
                    }
                }
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit Perl if/else with Phi variable declaration.
    # Phi(Region, val_a, val_b) becomes a my variable declared before the if,
    # assigned in each branch.
    method emit_cfg_phi_if($if_node, $phi) {
        my $cond = $if_node->inputs()->[1];
        my $cond_expr = $self->_emit_expr($cond);

        my $region = $phi->region();
        my $values = $phi->inputs();  # arrayref of [val_a, val_b]
        my $val_a_expr = $self->_emit_expr($values->[0]);
        my $val_b_expr = $self->_emit_expr($values->[1]);

        my $phi_var = '$_phi_' . $phi->id();

        my @lines;
        push @lines, "my $phi_var;";
        push @lines, "if ($cond_expr) {";
        push @lines, "    $phi_var = $val_a_expr;";
        push @lines, "} else {";
        push @lines, "    $phi_var = $val_b_expr;";
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit Perl loop from a Loop CFG node.
    # When iterator/list are present, emits foreach syntax.
    # $loop/$body_proj/$exit_proj: retained for future GCM/peephole passes.
    method emit_cfg_loop($loop, $loop_if, $body_proj, $exit_proj,
                         $body_stmts = [], $iterator = undef, $list = undef) {
        my @lines;

        if (defined $iterator && defined $list) {
            # Foreach loop: for my $var (list) { ... }
            my $iter_expr = $self->_emit_expr($iterator);
            my $list_expr;
            if (ref($list) eq 'ARRAY') {
                $list_expr = join(', ', map { $self->_emit_expr($_) } $list->@*);
            } else {
                $list_expr = $self->_emit_expr($list);
            }
            push @lines, "for my $iter_expr ($list_expr) {";
        } else {
            # While loop: while (cond) { ... }
            my $cond = $loop_if->inputs()->[1];
            my $cond_expr = $self->_emit_expr($cond);
            push @lines, "while ($cond_expr) {";
        }

        for my $stmt ($body_stmts->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }

    method _emit_backtick_expr($node) {
        my $command = $node->inputs()->[0];
        return '`' . $self->_emit_expr($command) . '`';
    }

    method _escape_single_quote($str) {
        $str =~ s/\\/\\\\/g;
        $str =~ s/'/\\'/g;
        return $str;
    }

    # Emit Perl code from a cfg_state entry.
    # Dispatches to emit_cfg_if or emit_cfg_loop based on which CFG node
    # references are present in the state.
    # Returns undef if the state has no control flow structure to emit.
    method emit_from_cfg_state($sa, $ctx) {
        my $state = $ctx->cfg_state();
        return unless defined $state;

        # If/else: cfg_state has if_node
        if (defined $state->{if_node}) {
            return $self->emit_cfg_if(
                $state->{if_node},
                $state->{true_proj},
                $state->{false_proj},
                $state->{then_stmts} // [],
                $state->{else_stmts} // [],
            );
        }

        # Loop: cfg_state has loop
        if (defined $state->{loop}) {
            return $self->emit_cfg_loop(
                $state->{loop},
                $state->{loop_if},
                $state->{body_proj},
                $state->{exit_proj},
                $state->{body_stmts} // [],
                $state->{iterator},
                $state->{list},
            );
        }

        # Try/catch: cfg_state has try_node
        if (defined $state->{try_node}) {
            return $self->emit_cfg_try_catch(
                $state->{try_stmts}   // [],
                $state->{catch_var},
                $state->{catch_stmts} // [],
            );
        }

        return;
    }

    # Emit Perl try { ... } catch ($var) { ... } from cfg_state.
    method emit_cfg_try_catch($try_stmts, $catch_var, $catch_stmts) {
        my @lines;
        push @lines, "try {";
        for my $stmt ($try_stmts->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "} catch ($catch_var) {";
        for my $stmt ($catch_stmts->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }
}
