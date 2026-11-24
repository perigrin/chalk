our $g=1; sub f { local $g=2; my $a=$_[0]; $a->[0] } use strict; eval { f("str") }; print "$g\n";
