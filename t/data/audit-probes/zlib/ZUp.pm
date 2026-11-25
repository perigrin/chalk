# ABOUTME: Library code for the z/pk probes: the same package in a module B::SoN
# ABOUTME: follows (an upper-case name), for comparison with zlow.
package ZUp;
our $n = 1;
sub bump  { $n++; return }
sub set   { $n = $_[0]; return }
sub get   { $n }
sub poke  { $main::g = $_[0]; return }
sub call  { $_[0]->() }
1;
