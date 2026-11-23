my $x=1; my $f=sub { $x*2 }; my $s=0; for my $i (1..3) { $x=$i; $s+=$f->() } print "$s\n";
