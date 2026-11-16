# ABOUTME: The LLVM target: lower() hands a typed SoN program to T2 (Chalk::Target::LLVM::Lower) and
# ABOUTME: returns its module text, or dies with T2's own named reason where T2 refuses the program.
package Chalk::Target::LLVM;
use 5.42.0;
use utf8;

# I4/I5: LLVM is the typed-IR-tier backend; it isa Chalk::IR::Target (not Chalk::Target).
# Chalk::Target is the Bootstrap-tier base (generate/generate_distribution);
# Chalk::IR::Target is the typed-IR-tier base (lower). Keeping them separate ensures
# Bootstrap targets do not inherit an alien lower() stub.
use parent 'Chalk::IR::Target';

use Chalk::Target::LLVM::Lower;

# lower($return_node, %opts) -> $llvm_ir_text
#
# T2 IS THE ARCHITECTURE (perigrin): a program is built as a graph typed in
# LLVM's types (Chalk::Target::LLVM::Builder) and printed (Printer). There is
# no other path. A program T2 does not take is refused as a GAP, by T2's own
# reason -- "GAP: T2: out of its slices (...)", or the GAP its builder raised --
# never lowered some other way, never emitted as nothing.
#
# %opts: mop => the sealed Chalk::MOP the program's classes and subs come
# from (Call nodes name their class; without it a class call is refused).
# Any other option is the caller's and is not read here.
sub lower {
    my ($class, $return_node, %opts) = @_;
    my $ir = Chalk::Target::LLVM::Lower->lower_program($return_node, mop => $opts{mop});
    return $ir if defined $ir;
    my $why = ( $Chalk::Target::LLVM::Lower::PATH // {} )->{why};
    $why = 'T2 refused the program' unless defined $why && length $why;
    # A REFUSAL IS A GAP, by the project's one convention (GAP-not-miscompile):
    # "GAP: " and T2's own reason, whole.
    die( ( $why =~ /\AGAP:/ ? $why : "GAP: $why" ) . "\n" );
}

1;
