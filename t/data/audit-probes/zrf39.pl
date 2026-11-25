my $x=1; my $c1=sub { $x++ }; my $c2=sub { $x*=10 }; $c1->(); $c2->(); $c1->(); print "$x\n";
