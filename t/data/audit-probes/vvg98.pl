sub ap { $_[0]->($_[1]) } my $t = 0; ap(sub { $t += $_[0] }, 5); ap(sub { $t *= $_[0] }, 3); print "$t\n";
