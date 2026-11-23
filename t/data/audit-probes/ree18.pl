my @a=(1,2,3); my $s=""; for my $x (@a) { $x=5 if $x==2; $s.=join("",@a)."," } print "$s\n";
