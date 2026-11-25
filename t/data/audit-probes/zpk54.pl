our $x=1; my $s=""; my $i=0; while ($i++<3) { $s.=$x; next if $i==1; $x*=2 } print "$s$x\n";
