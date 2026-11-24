my $n=0; my $z=0; sub cnt { $n++; 1 } my $r = eval { my $q = 5 % $z; cnt(); $q }; print "$n\n";
