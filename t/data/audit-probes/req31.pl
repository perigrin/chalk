our $g=1; sub f { local $g=2; my @a=(1); my $i=shift; $a[$i]->{x} } eval { use strict; f(0) }; print "$g\n";
