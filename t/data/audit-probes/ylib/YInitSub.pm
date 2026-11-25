# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a followed module whose file-level code calls its own subs to build its state.
package YInitSub;
our $v = compute(); our %reg; register("a"); register("b");
sub compute { 40 + 2 } sub register { $reg{ $_[0] } = keys(%reg) + 1; return } sub reg { join ",", map { "$_=$reg{$_}" } sort keys %reg }
1;
