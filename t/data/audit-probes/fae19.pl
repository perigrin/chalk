sub f { die "x\n" } my $x = eval { f(); 1 } ? "a" : "b"; print "$x\n";
