use feature 'try'; no warnings; my $x=0; for (1..3) { try { $x+=$_; die "x\n" if $_==2; $x+=10 } catch ($e) { $x+=100 } } print "$x\n";
