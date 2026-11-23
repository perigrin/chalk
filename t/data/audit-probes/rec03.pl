use strict; our $g=1; sub f { local $g=2; my $r=shift; my @a=@$r; 1 } eval { f(undef) }; print "$g\n";
