# ABOUTME: Phase 4b-3 end-to-end runner: corpus source -> B::SoN -> JSON -> Chalk -> lli == perl.
# ABOUTME: Validates the producible-now slice through the real producer (not the IR-block builder).
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON ();
use Chalk::Target::LLVM;
use Chalk::CodeGen::Pipeline;

# ---------------------------------------------------------------------------
# Environment gates
# ---------------------------------------------------------------------------
my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# ---------------------------------------------------------------------------
# What this file compares
#
# Each corpus case is a VALUE-UNDER-TEST EXPRESSION, not a program: its last
# statement is a bare expression whose value is the thing being checked. A
# program built from such a source prints NOTHING -- the producer correctly
# emits no code for a trailing expression in void context -- so the value has
# to be given a channel before either side can observe it.
#
# The channel is a `print` at SOURCE level, applied identically to both sides:
# the trailing expression becomes `print("[", EXPR, "]")`. Both the perl oracle
# and the lowered program then observe the same thing a real program's contract
# offers -- stdout. There is no type-tag channel on either side.
#
# The brackets are load-bearing: an expression that legitimately prints empty
# (a false Boolean, an undef) yields `[]`, which is distinguishable from a
# program that printed nothing at all (``). Without them those two collapse.
#
# WHAT PRINTING CANNOT SEE: printed output is the VALUE, not the
# REPRESENTATION. `Int:30` and `Num:30` both print `30`; a false Boolean and an
# undef both print empty. A case that exists to pin a repr rather than a value
# cannot be checked here -- see the repr note on the Pair case below.
# ---------------------------------------------------------------------------

# Split a corpus source into class definitions (kept at file scope) and the
# driver statements (wrapped as corpus_case). A `class Foo { ... }` compiled
# inside the wrapper sub generates a spurious loop, so class defs must stay at
# file scope. Returns ($head_lines, $driver_lines, \@class_names).
sub split_class_source ($clean) {
    my @lines = split /\n/, $clean;
    my (@head, @driver, @class_names);
    my $depth = 0;
    my $in_class = 0;
    for my $line (@lines) {
        if (!$in_class && $line =~ /^\s*(?:use|no)\s+/) {
            push @head, $line;            # pragmas stay at file scope
            next;
        }
        if (!$in_class && $line =~ /^\s*class\s+(\w[\w:]*)/) {
            push @class_names, $1;
            $in_class = 1;
            $depth = 0;
        }
        if ($in_class) {
            push @head, $line;
            $depth += ($line =~ tr/{//);
            $depth -= ($line =~ tr/}//);
            $in_class = 0 if $depth <= 0;
            next;
        }
        push @driver, $line;              # the executable driver
    }
    return (\@head, \@driver, \@class_names);
}

# Give the driver's trailing value-expression a channel: rewrite
#   STMT; STMT; EXPR      as      STMT; STMT; print("[", EXPR, "]");
#
# The split is on the LAST semicolon of the DRIVER text, so it never reaches
# inside a class body -- split_class_source has already moved those to @head.
# A driver that is a bare expression with no leading statements (`1 + 2`) has
# no semicolon and is wrapped whole.
sub print_wrap_driver ($driver) {
    my $text = join("\n", @$driver);
    $text =~ s/\s+$//;
    my ($head, $expr) = $text =~ /^(.*;)\s*([^;]+?)\s*$/s
        ? ($1, $2)
        : ('', $text);
    return join("\n", grep { length } $head, qq{print("[", ($expr), "]");});
}

# ---------------------------------------------------------------------------
# Chalk side: corpus source -> B::SoN -> JSON -> lowered LLVM -> lli stdout.
#
# program_mode is REQUIRED here: the case has been rewritten into a real
# program whose contract is what it prints. The type-tag epilogue would append
# a second, competing output channel that the perl oracle does not have.
# ---------------------------------------------------------------------------
sub run_through_bson ($source) {
    (my $clean = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean =~ s/\s+$//;

    my ($head, $driver, $class_names) = split_class_source($clean);
    my $prog = join("\n", @$head) . "\n"
             . "package main;\n"
             . "sub corpus_case {\n" . print_wrap_driver($driver) . "\n}\n";
    my @pkgs = ('package=main', map { "package=$_" } @$class_names);
    my $pkg_opts = join(',', @pkgs);

    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $prog;
    close $fh;

    my $json = qx($PERL -I$SON -MO=SoN,json,$pkg_opts $tmp 2>/dev/null);
    return (undef, "B::SoN produced no JSON") unless $json =~ /\S/;

    my $data = eval { JSON::PP->new->decode($json) };
    return (undef, "JSON decode failed: $@") unless $data;
    return (undef, "no main::corpus_case method")
        unless $data->{methods}{'main::corpus_case'};

    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::corpus_case'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::corpus_case', $ret ]);
    };

    my ($units, $graphs, undef, $load_err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    return (undef, $load_err) if $load_err;

    return (undef, "no loaded graph") unless $graphs->{'main::corpus_case'};
    return (undef, "no Return node")  unless @$units;
    my $unit = $units->[0];
    return (undef, "LLVM lowering GAP: $unit->{err}") unless $unit->{ok};
    my $ll = $unit->{ll};

    # Run the emitted IR through lli.
    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll;
    close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    my $exit = $? >> 8;
    return (undef, "lli exited $exit: $out") if $exit != 0;
    return ($out, undef);
}

# Perl oracle: run the SAME print-wrapped program under perl and take its stdout.
sub perl_oracle ($source) {
    (my $clean = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean =~ s/\s+$//;

    my ($head, $driver, undef) = split_class_source($clean);
    my $prog = "use 5.42.0;\nuse utf8;\n"
             . join("\n", @$head) . "\n"
             . print_wrap_driver($driver) . "\n";
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $prog;
    close $fh;
    my $out = qx($PERL $tmp 2>&1);
    return $out;
}

# ---------------------------------------------------------------------------
# The producible-now slice (4a gap map). Each case: a corpus source and whether
# we expect it to reach lli (GREEN) or to be an honest GAP at this stage.
# Cases are tagged so a GAP is recorded explicitly, never silently passed.
# ---------------------------------------------------------------------------
my @slice = (
    # arithmetic (perl constant-folds these to a single Constant)
    { topic => 'arithmetic', src => '1 + 2',  expect => 'green' },
    { topic => 'arithmetic', src => '5 - 3',  expect => 'green' },
    { topic => 'arithmetic', src => '3 * 4',  expect => 'green' },
    { topic => 'arithmetic', src => '3 / 4',  expect => 'green' },
    { topic => 'arithmetic', src => '-7 % 3', expect => 'green' },
    # statements (literals)
    { topic => 'statements',  src => '5',                 expect => 'green' },
    { topic => 'statements',  src => 'my $x = 1; my $y = 2; $x + $y', expect => 'green' },
    # variables
    { topic => 'variables',   src => 'my $x = 1; $x',     expect => 'green' },
    { topic => 'variables',   src => 'my $x; $x = 1; $x', expect => 'green' },
    { topic => 'variables',   src => 'my $x = 1; $x = 2; $x', expect => 'green' },
    # strings
    { topic => 'strings',     src => q{my $s = 'hello'; $s},     expect => 'green' },
    { topic => 'strings',     src => q{"hello" . " world"},      expect => 'green' },

    # Constant-folded comparisons: B::SoN recovers PL_sv_yes/PL_sv_no as a
    # Boolean Constant (4b-3b), and the LLVM backend lowers a Boolean constant to
    # i1, so these reach lli == perl. Printed, perl's true is `1` and its false is
    # the empty string, so these read as `[1]` and `[]` -- which is exactly why
    # the printed value is bracketed.
    { topic => 'statements',  src => '1 < 2', expect => 'green' },
    { topic => 'statements',  src => '2 < 1', expect => 'green' },

    # references R6/R7: array/hash element assignment. Under canonical ops
    # (4b-4) these are array-build (aassign -> ArrayRef) + element store
    # (aelem/helem lvalue + sassign -> Assign over Subscript) + element read.
    { topic => 'references', src => 'my @a = (1, 2, 3); $a[0] = 42; $a[0]', expect => 'green' },
    { topic => 'references', src => 'my %h = (k => 0); $h{k} = 99; $h{k}',  expect => 'green' },

    # variables C2: numeric compound assignment (`$x += 2`). Under canonical ops
    # (4b-5) this is a read-modify-write: the add over an lvalue $x rebinds $x.
    { topic => 'variables', src => 'my $x = 1; $x += 2; $x', expect => 'green' },

    # increment K1/K2: ++$i / $i++ are read-modify-write (preinc/predec ops,
    # NOT TARGMY). 4b-6 lowers them to Add/Subtract($i, 1) + rebind; both corpus
    # cases read $i after, so both expect 1.
    { topic => 'increment', src => 'my $i = 0; ++$i; $i', expect => 'green' },
    { topic => 'increment', src => 'my $i = 0; $i++; $i', expect => 'green' },

    # strings S4 (`$s .= 'b'`): a multiconcat with APPEND|TARGMY. 4b-4b handles
    # the TARGMY store-back (write result to the targ slot + rebind).
    { topic => 'strings', src => q{my $s = 'a'; $s .= 'b'; $s}, expect => 'green' },

    # scalar self-assign (`$x = $x + 1`): an add with TARGMY (OPpTARGET_MY),
    # writing its result in-place to the pad slot. 4b-4b rebinds the targ.
    { topic => 'variables', src => 'my $x = 5; $x = $x + 1; $x', expect => 'green' },

    # classes (4c): the no-default-no-ADJUST corpus cases. B::SoN -> classes
    # section -> sealed MOP -> backend lower(mop=>) == perl.
    { topic => 'classes',
      src => "use feature 'class';\nno warnings 'experimental::class';\n"
           . "class Greeter { method greet { 42 } }\n"
           . "my \$g = Greeter->new;\n\$g->greet",
      expect => 'green' },
    # field-basic: a method returning a field. Reaches lli and prints the field's
    # value; a printed program does not need the field's representation, only its
    # value, so this is green on the printed contract.
    { topic => 'classes',
      src => "use feature 'class';\nno warnings 'experimental::class';\n"
           . "class Animal { field \$name :param;\nmethod name { \$name } }\n"
           . "my \$a = Animal->new(name => 'cat');\n\$a->name",
      expect => 'green' },
    # field-attrs: :reader methods returning fields, added together.
    #
    # DECLARED GAP, and it is a REPRESENTATION gap, not a value gap: the fields
    # have no declared type, so the sum's repr comes out `Num` where perl's is
    # `Int`. The VALUE agrees on both sides (30) -- so on this file's printed
    # contract the case would pass, and the divergence it was written to catch
    # would go unobserved. It stays a GAP rather than being converted into a
    # green that proves nothing. Closing it needs field type inference (4c-1b);
    # the repr itself belongs in a repr-level test, not here.
    { topic => 'classes',
      src => "use feature 'class';\nno warnings 'experimental::class';\n"
           . "class Pair { field \$left :param :reader;\nfield \$right :param :reader; }\n"
           . "my \$p = Pair->new(left => 10, right => 20);\n\$p->left + \$p->right",
      expect => 'gap',
      gap => 'field has no declared type; sum reprs as Num where perl is Int '
           . '(a repr divergence printing cannot see -- needs field type inference)' },
    # class-isa: an inherited method call ($c->kind where kind is on the parent).
    # Resolves through the MRO and prints the parent method's value.
    { topic => 'classes',
      src => "use feature 'class';\nno warnings 'experimental::class';\n"
           . "class Base { method kind { 7 } }\n"
           . "class Child :isa(Base) { }\n"
           . "my \$c = Child->new;\n\$c->kind",
      expect => 'green' },
);

my %tally = (green => 0, gap => 0, bug => 0);

for my $case (@slice) {
    my $label = "$case->{topic}: $case->{src}";
    subtest $label => sub {
        my $oracle = perl_oracle($case->{src});
        # The bracketing makes this assertion real: a program that printed
        # nothing yields '', which fails here, while one that printed an empty
        # value yields '[]', which passes.
        like($oracle, qr/^\[.*\]$/s, "perl oracle printed a bracketed value ($oracle)");

        my ($lli, $err) = run_through_bson($case->{src});

        if ($case->{expect} eq 'green') {
            if (defined $lli) {
                is($lli, $oracle, "lli '$lli' == perl '$oracle'")
                    and $tally{green}++;
            }
            else {
                $tally{bug}++;
                fail("expected GREEN but pipeline failed: $err");
                diag("NEWLY-LOCALIZED PRODUCER/SEAM BUG: $label -> $err");
            }
        }
        else {
            # Declared GAP: record it honestly, do not assert lli==perl.
            $tally{gap}++;
            ok(1, "declared GAP (recorded, not silently passed): " . ($err // 'no error'));
            diag("GAP: $label" . (defined $err ? " -> $err" : ''));
        }
    };
}

diag("=== 4b-3 producible-now slice tally ===");
diag("GREEN (lli==perl): $tally{green}");
diag("GAP   (honest):    $tally{gap}");
diag("BUG   (localized): $tally{bug}");

done_testing();
