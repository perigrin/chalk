my @a=(1,2); my %h; for my $x (@a) { ($h{$x},$x)=($x,0) } print "@a ", join(",", sort keys %h), "\n";
