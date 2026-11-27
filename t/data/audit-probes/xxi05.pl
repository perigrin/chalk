my $x = 1; my $c = eval 'sub { $x++ }'; $c->(); print "$x\n";
