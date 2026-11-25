# ABOUTME: Library code for the z/pk probes: a plain package in a lower-case module
# ABOUTME: (one B::SoN does not follow) whose subs write and read package scalars.
package zlow;
our $n = 1;
our @l = (1);
sub bump   { $n++; return }
sub set    { $n = $_[0]; return }
sub get    { $n }
sub poke   { $main::g = $_[0]; return }
sub pokeq  { $ZQ::v = $_[0]; return }
sub addl   { push @l, $_[0]; return }
sub alias0 { $_[0] = "z"; return }
sub dies   { local $n = 99; die "zlow\n" }
sub call   { $_[0]->() }
1;
