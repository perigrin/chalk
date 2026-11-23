our $g=1; sub f { local $g=2; my $r=shift; use strict; $$r } eval { f("str") }; print "$g\n";
