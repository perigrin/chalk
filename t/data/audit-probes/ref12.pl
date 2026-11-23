my $x=0; my $f=sub { $x=1; 5 }; my @l=($x, $f->(), $x); print "@l\n";
