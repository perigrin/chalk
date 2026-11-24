our $g=1; sub f { local $g=2; my $r; use strict; my @a=@$r; 1 } eval { f() }; print "$g\n";
