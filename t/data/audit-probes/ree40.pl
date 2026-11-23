my @a=(1,2,3); sub g { join("",@a) } my $s=""; for my $x (@a) { $x.="!"; $s.=g()."," } print "$s\n";
