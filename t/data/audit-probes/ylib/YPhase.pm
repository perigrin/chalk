# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a followed module with INIT and END blocks.
package YPhase;
our $n = 1; INIT { $n = 9 } END { print "lib end\n" } sub get { $n }
1;
