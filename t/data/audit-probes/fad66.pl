our $g=1; sub f { local $g=2; my $r=$_[0]; my $n = @$r; $n } use strict; print eval { f([1,2]) }, $g; eval { f("s") }; print "$g\n";
