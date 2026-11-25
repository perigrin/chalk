my $s="a"; sub d { die "x\n" } eval { $s.="b"; d(); $s.="c" }; print "$s\n";
